package provertask

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/scroll-tech/da-codec/encoding"
	"github.com/scroll-tech/go-ethereum/log"
	"github.com/scroll-tech/go-ethereum/params"
	"gorm.io/gorm"

	"scroll-tech/common/types"
	"scroll-tech/common/types/message"
	"scroll-tech/common/utils"

	"scroll-tech/coordinator/internal/config"
	"scroll-tech/coordinator/internal/orm"
	coordinatorType "scroll-tech/coordinator/internal/types"
)

// ChunkProverTask the chunk prover task
type ChunkProverTask struct {
	BaseProverTask

	chunkTaskGetTaskTotal  *prometheus.CounterVec
	chunkTaskGetTaskProver *prometheus.CounterVec
}

// NewChunkProverTask new a chunk prover task
func NewChunkProverTask(cfg *config.Config, chainCfg *params.ChainConfig, db *gorm.DB, reg prometheus.Registerer) *ChunkProverTask {
	cp := &ChunkProverTask{
		BaseProverTask: BaseProverTask{
			db:                 db,
			cfg:                cfg,
			chainCfg:           chainCfg,
			chunkOrm:           orm.NewChunk(db),
			blockOrm:           orm.NewL2Block(db),
			proverTaskOrm:      orm.NewProverTask(db),
			proverBlockListOrm: orm.NewProverBlockList(db),
		},
		chunkTaskGetTaskTotal: promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
			Name: "coordinator_chunk_get_task_total",
			Help: "Total number of chunk get task.",
		}, []string{"fork_name"}),
		chunkTaskGetTaskProver: newGetTaskCounterVec(promauto.With(reg), "chunk"),
	}
	return cp
}

// Assign the chunk proof which need to prove
func (cp *ChunkProverTask) Assign(ctx *gin.Context, getTaskParameter *coordinatorType.GetTaskParameter) (*coordinatorType.GetTaskSchema, error) {
	taskCtx, err := cp.checkParameter(ctx)
	if err != nil || taskCtx == nil {
		return nil, fmt.Errorf("check prover task parameter failed, error:%w", err)
	}

	maxActiveAttempts := cp.cfg.ProverManager.ProversPerSession
	maxTotalAttempts := cp.cfg.ProverManager.SessionAttempts
	if strings.HasPrefix(taskCtx.ProverName, ExternalProverNamePrefix) {
		unassignedChunkCount, getCountError := cp.chunkOrm.GetUnassignedChunkCount(ctx.Copy(), maxActiveAttempts, maxTotalAttempts, getTaskParameter.ProverHeight)
		if getCountError != nil {
			log.Error("failed to get unassigned chunk proving tasks count", "height", getTaskParameter.ProverHeight, "err", err)
			return nil, ErrCoordinatorInternalFailure
		}
		// Assign external prover if unassigned task number exceeds threshold
		if unassignedChunkCount < cp.cfg.ProverManager.ExternalProverThreshold {
			return nil, nil
		}
	}

	var chunkTask *orm.Chunk
	for i := 0; i < 5; i++ {
		var getTaskError error
		var tmpChunkTask *orm.Chunk
		var assignedOffset, unassignedOffset = 0, 0
		tmpAssignedChunkTasks, getTaskError := cp.chunkOrm.GetAssignedChunks(ctx.Copy(), maxActiveAttempts, maxTotalAttempts, getTaskParameter.ProverHeight, 50)
		if getTaskError != nil {
			log.Error("failed to get assigned chunk proving tasks", "height", getTaskParameter.ProverHeight, "err", getTaskError)
			return nil, ErrCoordinatorInternalFailure
		}
		// Why here need get again? In order to support a task can assign to multiple prover, need also assign `ProvingTaskAssigned`
		// chunk to prover. But use `proving_status in (1, 2)` will not use the postgres index. So need split the sql.
		tmpUnassignedChunkTask, getTaskError := cp.chunkOrm.GetUnassignedChunk(ctx.Copy(), maxActiveAttempts, maxTotalAttempts, getTaskParameter.ProverHeight, 50)
		if getTaskError != nil {
			log.Error("failed to get unassigned chunk proving tasks", "height", getTaskParameter.ProverHeight, "err", getTaskError)
			return nil, ErrCoordinatorInternalFailure
		}
		for {
			tmpChunkTask = nil
			if assignedOffset < len(tmpAssignedChunkTasks) {
				tmpChunkTask = tmpAssignedChunkTasks[assignedOffset]
				assignedOffset++
			} else if unassignedOffset < len(tmpUnassignedChunkTask) {
				tmpChunkTask = tmpUnassignedChunkTask[unassignedOffset]
				unassignedOffset++
			}

			if tmpChunkTask == nil {
				log.Debug("get empty chunk", "height", getTaskParameter.ProverHeight)
				return nil, nil
			}

			// Don't dispatch the same failing job to the same prover
			proverTask, getTaskError := cp.proverTaskOrm.GetTaskOfProver(ctx.Copy(), message.ProofTypeChunk, tmpChunkTask.Hash, taskCtx.PublicKey, taskCtx.ProverVersion)
			if getTaskError != nil {
				log.Error("failed to get prover task of prover", "proof_type", message.ProofTypeChunk.String(), "taskID", tmpChunkTask.Hash, "key", taskCtx.PublicKey, "Prover_version", taskCtx.ProverVersion, "error", getTaskError)
				return nil, ErrCoordinatorInternalFailure
			}
			if proverTask == nil || types.ProverProveStatus(proverTask.ProvingStatus) != types.ProverProofInvalid {
				break
			}
		}

		rowsAffected, updateAttemptsErr := cp.chunkOrm.UpdateChunkAttempts(ctx.Copy(), tmpChunkTask.Index, tmpChunkTask.ActiveAttempts, tmpChunkTask.TotalAttempts)
		if updateAttemptsErr != nil {
			log.Error("failed to update chunk attempts", "height", getTaskParameter.ProverHeight, "err", updateAttemptsErr)
			return nil, ErrCoordinatorInternalFailure
		}

		if rowsAffected == 0 {
			time.Sleep(100 * time.Millisecond)
			continue
		}

		chunkTask = tmpChunkTask
		break
	}

	if chunkTask == nil {
		log.Debug("get empty unassigned chunk after retry 5 times", "height", getTaskParameter.ProverHeight)
		return nil, nil
	}

	log.Info("start chunk generation session", "task_id", chunkTask.Hash, "public key", taskCtx.PublicKey, "prover name", taskCtx.ProverName)

	hardForkName, getHardForkErr := cp.hardForkName(ctx, chunkTask)
	if getHardForkErr != nil {
		cp.recoverActiveAttempts(ctx, chunkTask)
		log.Error("retrieve hard fork name by chunk failed", "task_id", chunkTask.Hash, "err", getHardForkErr)
		return nil, ErrCoordinatorInternalFailure
	}

	//if _, ok := taskCtx.HardForkNames[hardForkName]; !ok {
	//	cp.recoverActiveAttempts(ctx, chunkTask)
	//	log.Error("incompatible prover version",
	//		"requisite hard fork name", hardForkName,
	//		"prover hard fork name", taskCtx.HardForkNames,
	//		"task_id", chunkTask.Hash)
	//	return nil, ErrCoordinatorInternalFailure
	//}

	proverTask := orm.ProverTask{
		TaskID:          chunkTask.Hash,
		ProverPublicKey: taskCtx.PublicKey,
		TaskType:        int16(message.ProofTypeChunk),
		ProverName:      taskCtx.ProverName,
		ProverVersion:   taskCtx.ProverVersion,
		ProvingStatus:   int16(types.ProverAssigned),
		FailureType:     int16(types.ProverTaskFailureTypeUndefined),
		// here why need use UTC time. see scroll/common/database/db.go
		AssignedAt: utils.NowUTC(),
	}

	if err = cp.proverTaskOrm.InsertProverTask(ctx.Copy(), &proverTask); err != nil {
		cp.recoverActiveAttempts(ctx, chunkTask)
		log.Error("insert chunk prover task fail", "task_id", chunkTask.Hash, "publicKey", taskCtx.PublicKey, "err", err)
		return nil, ErrCoordinatorInternalFailure
	}

	taskMsg, err := cp.formatProverTask(ctx.Copy(), &proverTask, hardForkName)
	if err != nil {
		cp.recoverActiveAttempts(ctx, chunkTask)
		log.Error("format prover task failure", "task_id", chunkTask.Hash, "err", err)
		return nil, ErrCoordinatorInternalFailure
	}

	cp.chunkTaskGetTaskTotal.WithLabelValues(hardForkName).Inc()
	cp.chunkTaskGetTaskProver.With(prometheus.Labels{
		coordinatorType.LabelProverName:      proverTask.ProverName,
		coordinatorType.LabelProverPublicKey: proverTask.ProverPublicKey,
		coordinatorType.LabelProverVersion:   proverTask.ProverVersion,
	}).Inc()

	return taskMsg, nil
}

func (cp *ChunkProverTask) hardForkName(ctx *gin.Context, chunkTask *orm.Chunk) (string, error) {
	l2Block, getBlockErr := cp.blockOrm.GetL2BlockByNumber(ctx.Copy(), chunkTask.StartBlockNumber)
	if getBlockErr != nil {
		return "", getBlockErr
	}
	hardForkName := encoding.GetHardforkName(cp.chainCfg, l2Block.Number, l2Block.BlockTimestamp)
	return hardForkName, nil
}

func (cp *ChunkProverTask) formatProverTask(ctx context.Context, task *orm.ProverTask, hardForkName string) (*coordinatorType.GetTaskSchema, error) {
	// Get block hashes.
	blockHashes, dbErr := cp.blockOrm.GetL2BlockHashesByChunkHash(ctx, task.TaskID)
	if dbErr != nil || len(blockHashes) == 0 {
		return nil, fmt.Errorf("failed to fetch block hashes of a chunk, chunk hash:%s err:%w", task.TaskID, dbErr)
	}

	taskDetail := message.ChunkTaskDetail{
		BlockHashes: blockHashes,
	}
	blockHashesBytes, err := json.Marshal(taskDetail)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal block hashes hash:%s, err:%w", task.TaskID, err)
	}

	proverTaskSchema := &coordinatorType.GetTaskSchema{
		UUID:         task.UUID.String(),
		TaskID:       task.TaskID,
		TaskType:     int(message.ProofTypeChunk),
		TaskData:     string(blockHashesBytes),
		HardForkName: hardForkName,
	}

	return proverTaskSchema, nil
}

func (cp *ChunkProverTask) recoverActiveAttempts(ctx *gin.Context, chunkTask *orm.Chunk) {
	if err := cp.chunkOrm.DecreaseActiveAttemptsByHash(ctx, chunkTask.Hash); err != nil {
		log.Error("failed to recover chunk active attempts", "hash", chunkTask.Hash, "error", err)
	}
}
