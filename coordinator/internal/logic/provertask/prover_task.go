package provertask

import (
	"fmt"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/scroll-tech/go-ethereum/log"
	"gorm.io/gorm"

	"scroll-tech/common/version"

	"scroll-tech/coordinator/internal/config"
	"scroll-tech/coordinator/internal/orm"
	coordinatorType "scroll-tech/coordinator/internal/types"
)

var (
	// ErrCoordinatorInternalFailure coordinator internal db failure
	ErrCoordinatorInternalFailure = fmt.Errorf("coordinator internal error")
	// ErrHardForkName indicates client request with the wrong hard fork name
	ErrHardForkName = fmt.Errorf("wrong hard fork name")
)

// ProverTask the interface of a collector who send data to prover
type ProverTask interface {
	Assign(ctx *gin.Context, getTaskParameter *coordinatorType.GetTaskParameter) (*coordinatorType.GetTaskSchema, error)
}

// BaseProverTask a base prover task which contain series functions
type BaseProverTask struct {
	cfg *config.Config
	db  *gorm.DB

	vkMap       map[string]string
	nameForkMap map[string]uint64
	forkHeights []uint64

	batchOrm           *orm.Batch
	chunkOrm           *orm.Chunk
	blockOrm           *orm.L2Block
	proverTaskOrm      *orm.ProverTask
	proverBlockListOrm *orm.ProverBlockList
}

type proverTaskContext struct {
	PublicKey     string
	ProverName    string
	ProverVersion string
	HardForkName  string
	// Warning: after setting AcceptVersions, the ProverVersion and HardForkName above should not exist
	// since these fields can only get concrete value after get_task is called.
	// using above fields shall take a lot of care.
	AcceptVersions [2]coordinatorType.AcceptVersion
}

func (c *proverTaskContext) hardForkNames() [2]string {
	return [2]string{c.AcceptVersions[0].HardForkName, c.AcceptVersions[1].HardForkName}
}

func (c *proverTaskContext) getProverVersion(hardForkName string) string {
	for i := 0; i < 2; i++ {
		if hardForkName == c.AcceptVersions[i].HardForkName {
			return c.AcceptVersions[i].ProverVersion
		}
	}
	return c.ProverVersion
}

func (b *BaseProverTask) checkVK(hardForkName string, vkInParam string) error {
	vk, vkExist := b.vkMap[hardForkName]
	if !vkExist {
		return fmt.Errorf("can't get vk for hard fork:%s, vkMap:%v", hardForkName, b.vkMap)
	}

	// if the prover has a different vk
	if vkInParam != vk {
		log.Error("vk inconsistency", "prover vk", vkInParam, "vk", vk, "hardForkName", hardForkName)
		// if the prover reports a different prover version
		// if !version.CheckScrollProverVersion(proverVersion.(string)) {
		// 	return nil, fmt.Errorf("incompatible prover version. please upgrade your prover, expect version: %s, actual version: %s", version.Version, proverVersion.(string))
		// }
		// if the prover reports a same prover version
		return fmt.Errorf("incompatible vk. please check your params files or config files")
	}
	return nil
}

// checkParameter check the prover task parameter illegal
func (b *BaseProverTask) checkParameter(ctx *gin.Context, getTaskParameter *coordinatorType.GetTaskParameter) (*proverTaskContext, error) {
	var ptc proverTaskContext

	publicKey, publicKeyExist := ctx.Get(coordinatorType.PublicKey)
	if !publicKeyExist {
		return nil, fmt.Errorf("get public key from context failed")
	}
	ptc.PublicKey = publicKey.(string)

	proverName, proverNameExist := ctx.Get(coordinatorType.ProverName)
	if !proverNameExist {
		return nil, fmt.Errorf("get prover name from context failed")
	}
	ptc.ProverName = proverName.(string)

	acceptVersions, acceptVersionsExist := ctx.Get(coordinatorType.AcceptVersions)
	if acceptVersionsExist {
		versions := acceptVersions.([]coordinatorType.AcceptVersion)
		if len(versions) != 2 {
			return nil, fmt.Errorf("there must exists two accept versions")
		}
		if len(getTaskParameter.VKs) != len(versions) {
			return nil, fmt.Errorf("parameter lack vks")
		}
		ptc.AcceptVersions = [2]coordinatorType.AcceptVersion{versions[0], versions[1]}
		// only check the first is enough
		if !version.CheckScrollRepoVersion(ptc.AcceptVersions[0].ProverVersion, b.cfg.ProverManager.MinProverVersion) {
			return nil, fmt.Errorf("incompatible prover version. please upgrade your prover, minimum allowed version: %s, actual version: %s", b.cfg.ProverManager.MinProverVersion, ptc.AcceptVersions[0].ProverVersion)
		}
		for i, version := range ptc.AcceptVersions {
			if err := b.checkVK(version.HardForkName, getTaskParameter.VKs[i]); err != nil {
				return nil, err
			}
		}
	} else {
		proverVersion, proverVersionExist := ctx.Get(coordinatorType.ProverVersion)
		if !proverVersionExist {
			return nil, fmt.Errorf("get prover version from context failed")
		}
		ptc.ProverVersion = proverVersion.(string)

		hardForkName, hardForkNameExist := ctx.Get(coordinatorType.HardForkName)
		if !hardForkNameExist {
			return nil, fmt.Errorf("get hard fork name from context failed")
		}
		ptc.HardForkName = hardForkName.(string)

		if !version.CheckScrollRepoVersion(proverVersion.(string), b.cfg.ProverManager.MinProverVersion) {
			return nil, fmt.Errorf("incompatible prover version. please upgrade your prover, minimum allowed version: %s, actual version: %s", b.cfg.ProverManager.MinProverVersion, proverVersion.(string))
		}

		vk, vkExist := b.vkMap[ptc.HardForkName]
		if !vkExist {
			return nil, fmt.Errorf("can't get vk for hard fork:%s, vkMap:%v", ptc.HardForkName, b.vkMap)
		}

		// if the prover has a different vk
		if getTaskParameter.VK != vk {
			log.Error("vk inconsistency", "prover vk", getTaskParameter.VK, "vk", vk, "hardForkName", ptc.HardForkName)
			// if the prover reports a different prover version
			if !version.CheckScrollProverVersion(proverVersion.(string)) {
				return nil, fmt.Errorf("incompatible prover version. please upgrade your prover, expect version: %s, actual version: %s", version.Version, proverVersion.(string))
			}
			// if the prover reports a same prover version
			return nil, fmt.Errorf("incompatible vk. please check your params files or config files")
		}
	}

	isBlocked, err := b.proverBlockListOrm.IsPublicKeyBlocked(ctx.Copy(), publicKey.(string))
	if err != nil {
		return nil, fmt.Errorf("failed to check whether the public key %s is blocked before assigning a chunk task, err: %w, proverName: %s", publicKey, err, proverName)
	}
	if isBlocked {
		return nil, fmt.Errorf("public key %s is blocked from fetching tasks. ProverName: %s", publicKey, proverName)
	}

	isAssigned, err := b.proverTaskOrm.IsProverAssigned(ctx.Copy(), publicKey.(string))
	if err != nil {
		return nil, fmt.Errorf("failed to check if prover %s is assigned a task, err: %w", publicKey.(string), err)
	}

	if isAssigned {
		return nil, fmt.Errorf("prover with publicKey %s is already assigned a task. ProverName: %s", publicKey, proverName)
	}
	return &ptc, nil
}

func (b *BaseProverTask) getHardForkNumberByName(forkName string) (uint64, error) {
	// when the first hard fork upgrade, the prover don't pass the fork_name to coordinator.
	// so coordinator need to be compatible.
	if forkName == "" {
		return 0, nil
	}

	hardForkNumber, exist := b.nameForkMap[forkName]
	if !exist {
		return 0, ErrHardForkName
	}

	return hardForkNumber, nil
}

var (
	getTaskCounterInitOnce sync.Once
	getTaskCounterVec      *prometheus.CounterVec = nil
)

func newGetTaskCounterVec(factory promauto.Factory, taskType string) *prometheus.CounterVec {
	getTaskCounterInitOnce.Do(func() {
		getTaskCounterVec = factory.NewCounterVec(prometheus.CounterOpts{
			Name: "coordinator_get_task_count",
			Help: "Multi dimensions get task counter.",
		}, []string{"task_type",
			coordinatorType.LabelProverName,
			coordinatorType.LabelProverPublicKey,
			coordinatorType.LabelProverVersion})
	})

	return getTaskCounterVec.MustCurryWith(prometheus.Labels{"task_type": taskType})
}
