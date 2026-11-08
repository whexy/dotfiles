// Command dotfiles-upgraded keeps one host converged on the upstream dotfiles
// repository: it learns of commits that passed CI, from CI's announcements or
// by polling GitHub, and runs the platform's rebuild command.
//
// `dotfiles-upgraded announce` is the CI side: it signs and publishes the
// announcement of a passing commit.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"dotfiles-upgraded/internal/announce"
	"dotfiles-upgraded/internal/engine"
	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/report"
	"dotfiles-upgraded/internal/state"
	"dotfiles-upgraded/internal/switcher"
)

func main() {
	command := run
	if len(os.Args) > 1 && os.Args[1] == "announce" {
		command = runAnnounce
	}
	if err := command(); err != nil {
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
	failureWebhook  string
	webhookToken    string
	notifyURL       string
	notifyPublicKey string
	notifiedPoll    time.Duration
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
	flag.StringVar(&opt.failureWebhook, "failure-webhook", "", "URL to POST a commit this host gave up switching to")
	flag.StringVar(&opt.webhookToken, "failure-webhook-token-file", "", "file holding the failure webhook's bearer token")
	flag.StringVar(&opt.notifyURL, "notify-url", "", "ntfy topic URL carrying CI's announcements; empty polls GitHub only")
	flag.StringVar(&opt.notifyPublicKey, "notify-public-key", "", "base64 ed25519 key announcements must be signed with")
	flag.DurationVar(&opt.notifiedPoll, "notified-poll-interval", 6*time.Hour, "interval between ref checks while the announcement stream is healthy")
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

	var notifyKey []byte
	if opt.notifyURL != "" {
		key, err := announce.ParsePublicKey(opt.notifyPublicKey)
		if err != nil {
			return fmt.Errorf("--notify-public-key: %w", err)
		}
		notifyKey = key
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
		ExitAfterSwitch:      opt.exitAfterSwitch,
		Ref:                  opt.ref,
		PollInterval:         opt.pollInterval,
		NotifiedPollInterval: opt.notifiedPoll,
		MaxAttempts:          opt.maxAttempts,
		RequireCIPass:        opt.requireCIPass,
		PendingTimeout:       opt.pendingTimeout,
		JitterSeed:           hostname + "/" + opt.configuration,
	}, client, sw, store, realClock{}, log)
	if opt.failureWebhook != "" {
		eng.Reporter = &report.Webhook{
			URL:           opt.failureWebhook,
			TokenFile:     opt.webhookToken,
			Host:          hostname,
			Configuration: opt.configuration,
			Mode:          string(mode),
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if opt.notifyURL != "" {
		sub := announce.NewSubscriber(opt.notifyURL, notifyKey, opt.repo, opt.ref, log)
		eng.Notifier = sub
		go sub.Run(ctx)
	}

	log.Info("starting",
		"mode", string(mode),
		"configuration", opt.configuration,
		"repo", opt.repo,
		"ref", opt.ref,
		"pollInterval", opt.pollInterval.String(),
		"authenticated", os.Getenv("GITHUB_TOKEN") != "",
		"failureWebhook", opt.failureWebhook,
		"notifyURL", opt.notifyURL,
		"statusFile", store.StatusPath(),
	)

	eng.Run(ctx)
	log.Info("stopped")
	return nil
}

// runAnnounce signs the announcement of a commit that passed CI and publishes
// it. The signing key and the relay's token arrive in the environment, which
// is how Woodpecker hands a step its secrets.
func runAnnounce() error {
	fs := flag.NewFlagSet("announce", flag.ExitOnError)
	url := fs.String("url", "", "ntfy topic URL to publish to (required)")
	repo := fs.String("repo", "whexy/dotfiles", "GitHub owner/name the commit belongs to")
	ref := fs.String("ref", "master", "branch the commit is the tip of")
	sha := fs.String("sha", "", "commit that passed CI (required)")
	seq := fs.Int64("seq", 0, "CI pipeline number, which orders announcements (required)")
	publicKey := fs.String("public-key", "", "base64 ed25519 key hosts verify with; refuses to publish when the signing key does not match it")
	fs.Parse(os.Args[2:])
	if *url == "" || *sha == "" || *seq <= 0 {
		return fmt.Errorf("announce needs --url, --sha and a positive --seq")
	}

	key, err := announce.ParsePrivateKey(os.Getenv("ROLLOUT_SIGNING_KEY"))
	if err != nil {
		return fmt.Errorf("ROLLOUT_SIGNING_KEY: %w", err)
	}
	if *publicKey != "" {
		want, err := announce.ParsePublicKey(*publicKey)
		if err != nil {
			return fmt.Errorf("--public-key: %w", err)
		}
		if !want.Equal(key.Public()) {
			return fmt.Errorf("ROLLOUT_SIGNING_KEY does not match --public-key; hosts would reject the announcement")
		}
	}
	token := os.Getenv("NTFY_ROLLOUT_TOKEN")
	if token == "" {
		return fmt.Errorf("NTFY_ROLLOUT_TOKEN is empty")
	}

	message, err := announce.Sign(key, announce.Announcement{
		Repo: *repo,
		Ref:  *ref,
		Sha:  *sha,
		Seq:  *seq,
		Time: time.Now().UTC(),
	})
	if err != nil {
		return err
	}

	client := &http.Client{Timeout: 30 * time.Second}
	for attempt := 1; ; attempt++ {
		err = announce.Publish(context.Background(), client, *url, token, message)
		if err == nil {
			fmt.Printf("announced %s (seq %d) to %s\n", *sha, *seq, *url)
			return nil
		}
		if attempt == 3 {
			return fmt.Errorf("publish: %w", err)
		}
		fmt.Fprintf(os.Stderr, "publish attempt %d failed: %v\n", attempt, err)
		time.Sleep(time.Duration(attempt) * 10 * time.Second)
	}
}
