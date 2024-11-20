package app

import (
	"context"
	"fmt"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/scroll-tech/go-ethereum/ethclient"
	"github.com/scroll-tech/go-ethereum/log"
	"github.com/urfave/cli/v2"

	"scroll-tech/common/database"
	"scroll-tech/common/observability"
	"scroll-tech/common/utils"
	"scroll-tech/common/version"
	"scroll-tech/rollup/internal/config"
	"scroll-tech/rollup/internal/controller/permissionless_batches"
	"scroll-tech/rollup/internal/controller/watcher"
)

var app *cli.App

func init() {
	// Set up rollup-relayer app info.
	app = cli.NewApp()
	app.Action = action
	app.Name = "permissionless-batches"
	app.Usage = "The Scroll Rollup Relayer for permissionless batch production"
	app.Version = version.Version
	app.Flags = append(app.Flags, utils.CommonFlags...)
	app.Flags = append(app.Flags, utils.RollupRelayerFlags...)
	app.Commands = []*cli.Command{}
	app.Before = func(ctx *cli.Context) error {
		return utils.LogSetup(ctx)
	}
}

func action(ctx *cli.Context) error {
	// Load config file.
	cfgFile := ctx.String(utils.ConfigFileFlag.Name)
	cfg, err := config.NewConfig(cfgFile)
	if err != nil {
		log.Crit("failed to load config file", "config file", cfgFile, "error", err)
	}

	subCtx, cancel := context.WithCancel(ctx.Context)
	defer cancel()

	// Make sure the required fields are set.
	if cfg.RecoveryConfig.L1BlockHeight == 0 {
		return fmt.Errorf("L1 block height must be specified")
	}
	if cfg.RecoveryConfig.LatestFinalizedBatch == 0 {
		return fmt.Errorf("latest finalized batch must be specified")
	}

	// init db connection
	db, err := database.InitDB(cfg.DBConfig)
	if err != nil {
		log.Crit("failed to init db connection", "err", err)
	}
	defer func() {
		if err = database.CloseDB(db); err != nil {
			log.Crit("failed to close db connection", "error", err)
		}
	}()

	registry := prometheus.DefaultRegisterer
	observability.Server(ctx, db)

	genesisPath := ctx.String(utils.Genesis.Name)
	genesis, err := utils.ReadGenesis(genesisPath)
	if err != nil {
		log.Crit("failed to read genesis", "genesis file", genesisPath, "error", err)
	}

	chunkProposer := watcher.NewChunkProposer(subCtx, cfg.L2Config.ChunkProposerConfig, genesis.Config, db, registry)
	batchProposer := watcher.NewBatchProposer(subCtx, cfg.L2Config.BatchProposerConfig, genesis.Config, db, registry)
	bundleProposer := watcher.NewBundleProposer(subCtx, cfg.L2Config.BundleProposerConfig, genesis.Config, db, registry)

	// Init l2geth connection
	l2client, err := ethclient.Dial(cfg.L2Config.Endpoint)
	if err != nil {
		return fmt.Errorf("failed to connect to L2geth at RPC=%s: %w", cfg.L2Config.Endpoint, err)
	}

	l2Watcher := watcher.NewL2WatcherClient(subCtx, l2client, cfg.L2Config.Confirmations, cfg.L2Config.L2MessageQueueAddress, cfg.L2Config.WithdrawTrieRootSlot, genesis.Config, db, registry)

	recovery := permissionless_batches.NewRecovery(subCtx, cfg, genesis, db, chunkProposer, batchProposer, bundleProposer, l2Watcher)

	if recovery.RecoveryNeeded() {
		if err = recovery.Run(); err != nil {
			return fmt.Errorf("failed to run recovery: %w", err)
		}
		log.Info("Success! You're ready to generate proofs!")
	} else {
		// TODO: implement batch submission if proofs are available
		log.Info("TODO: Batch submission")
	}

	return nil
}

// Run rollup relayer cmd instance.
func Run() {
	if err := app.Run(os.Args); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
