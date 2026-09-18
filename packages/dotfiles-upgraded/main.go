// Command dotfiles-upgraded keeps one host converged on the upstream dotfiles
// repository: it polls the tracked branch, waits for CI to pass, and runs the
// platform's rebuild command.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"dotfiles-upgraded/internal/engine"
	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
	"dotfiles-upgraded/internal/switcher"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "dotfiles-upgraded: "+err.Error())
		os.Exit(1)
	}
}

type options struct {
	exitAfterSwitch bool
	mode            string
	configuration   string
	flakeRef        string
	repo            string
	ref             string
	stateDir        string
	pollInterval    time.Duration
	maxAttempts     int
	requireCIPass   bool
	switchTimeout   time.Duration
	pendingTimeout  time.Duration
}

func run() error {
	var opt options
	flag.StringVar(&opt.mode, "mode", "", "rebuild mode: nixos, darwin or home-manager (required)")
	flag.StringVar(&opt.configuration, "configuration", "", "flake output name to switch to, e.g. mudd or wenxuan@mars (required)")
	flag.StringVar(&opt.flakeRef, "flake", "github:whexy/dotfiles", "flake reference to switch to")
	flag.StringVar(&opt.repo, "repo", "whexy/dotfiles", "GitHub owner/name used for API queries")
	flag.StringVar(&opt.ref, "ref", "master", "tracked branch")
	flag.StringVar(&opt.stateDir, "state-dir", "", "directory holding state.json, status.json and the switch lock (required)")
	flag.DurationVar(&opt.pollInterval, "poll-interval", 10*time.Minute, "base interval between ref checks")
	flag.IntVar(&opt.maxAttempts, "max-attempts", 3, "switch attempts before a commit is ignored")
	flag.BoolVar(&opt.requireCIPass, "require-ci-pass", true, "only switch to commits whose GitHub commit status is success")
	flag.DurationVar(&opt.switchTimeout, "switch-timeout", 6*time.Hour, "hard limit on a single rebuild")
	flag.DurationVar(&opt.pendingTimeout, "pending-timeout", 2*time.Hour, "give up on a commit whose CI stays pending this long")
	flag.BoolVar(&opt.exitAfterSwitch, "exit-after-switch", false, "exit after a successful switch so a stable supervisor can reload the active binary")
	flag.Parse()

	if opt.mode == "" {
		return fmt.Errorf("--mode is required")
	}
	mode, err := switcher.ParseMode(opt.mode)
	if err != nil {
		return err
	}
	if opt.configuration == "" {
		return fmt.Errorf("--configuration is required")
	}
	if opt.stateDir == "" {
		return fmt.Errorf("--state-dir is required")
	}
	if opt.pollInterval <= 0 {
		return fmt.Errorf("--poll-interval must be positive")
	}
	if opt.maxAttempts < 1 {
		return fmt.Errorf("--max-attempts must be at least 1")
	}

	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))

	store, err := state.NewStore(opt.stateDir, log)
	if err != nil {
		return err
	}

	hostname, err := os.Hostname()
	if err != nil {
		hostname = opt.configuration
	}

	client := github.New(opt.repo, os.Getenv("GITHUB_TOKEN"), nil)
	sw := &switcher.Exec{
		Mode:          mode,
		FlakeRef:      opt.flakeRef,
		Configuration: opt.configuration,
		LockPath:      store.LockPath(),
		Timeout:       opt.switchTimeout,
		Log:           log,
	}

	eng := engine.New(engine.Config{
		ExitAfterSwitch: opt.exitAfterSwitch,
		Ref:             opt.ref,
		PollInterval:    opt.pollInterval,
		MaxAttempts:     opt.maxAttempts,
		RequireCIPass:   opt.requireCIPass,
		PendingTimeout:  opt.pendingTimeout,
		JitterSeed:      hostname + "/" + opt.configuration,
	}, client, sw, store, realClock{}, log)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	log.Info("starting",
		"mode", string(mode),
		"configuration", opt.configuration,
		"repo", opt.repo,
		"ref", opt.ref,
		"pollInterval", opt.pollInterval.String(),
		"authenticated", os.Getenv("GITHUB_TOKEN") != "",
		"statusFile", store.StatusPath(),
	)

	eng.Run(ctx)
	log.Info("stopped")
	return nil
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now() }

func (realClock) Sleep(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
