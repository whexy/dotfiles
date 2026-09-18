// Package switcher runs the per-platform rebuild. It is the only part of the
// daemon that is platform specific, and the mode is configured rather than
// autodetected so a misdetection cannot switch a host the wrong way.
package switcher

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// Mode selects the rebuild command.
type Mode string

const (
	ModeNixOS       Mode = "nixos"
	ModeDarwin      Mode = "darwin"
	ModeHomeManager Mode = "home-manager"
)

// ParseMode validates a --mode value.
func ParseMode(s string) (Mode, error) {
	switch Mode(s) {
	case ModeNixOS, ModeDarwin, ModeHomeManager:
		return Mode(s), nil
	default:
		return "", fmt.Errorf("unknown mode %q (want nixos, darwin or home-manager)", s)
	}
}

// Command returns the argv for a mode. The flake ref is pinned to the gated
// SHA (github:owner/repo/<sha>) so the host builds exactly the commit whose CI
// status passed, not whatever the branch tip is by the time the build starts.
func Command(mode Mode, flakeRef, configuration, sha string) []string {
	flakeRef = flakeRef + "/" + sha
	switch mode {
	case ModeNixOS:
		return []string{"nixos-rebuild", "switch", "--refresh", "--flake", flakeRef + "#" + configuration}
	case ModeDarwin:
		return []string{"darwin-rebuild", "switch", "--refresh", "--flake", flakeRef + "#" + configuration}
	case ModeHomeManager:
		return []string{"nh", "home", "switch", flakeRef, "--refresh", "--no-nom", "-c", configuration, "-b", "backup"}
	default:
		return nil
	}
}

// Exec runs the rebuild for one host.
type Exec struct {
	Mode          Mode
	FlakeRef      string
	Configuration string
	LockPath      string
	Timeout       time.Duration
	Log           *slog.Logger
}

// Switch builds and activates sha's configuration.
func (e *Exec) Switch(ctx context.Context, sha string) error {
	argv := Command(e.Mode, e.FlakeRef, e.Configuration, sha)
	if argv == nil {
		return fmt.Errorf("no command for mode %q", e.Mode)
	}

	if e.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, e.Timeout)
		defer cancel()
	}

	unlock, err := lock(ctx, e.LockPath)
	if err != nil {
		return err
	}
	defer unlock()

	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	// A rebuild forks nix and activation scripts; killing only the direct
	// child would leave them running (and holding our pipes), so the whole
	// process group is signalled on cancellation.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	}
	cmd.WaitDelay = 10 * time.Second
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	e.Log.Info("switch starting", "sha", sha, "command", argv)
	started := time.Now()
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start %s: %w", argv[0], err)
	}

	done := make(chan struct{}, 2)
	go func() { e.stream(stdout, "stdout"); done <- struct{}{} }()
	go func() { e.stream(stderr, "stderr"); done <- struct{}{} }()
	<-done
	<-done

	if err := cmd.Wait(); err != nil {
		if ctxErr := ctx.Err(); errors.Is(ctxErr, context.DeadlineExceeded) {
			return fmt.Errorf("switch timed out after %s", e.Timeout)
		} else if ctxErr != nil {
			return ctxErr
		}
		return fmt.Errorf("switch failed after %s: %w", time.Since(started).Round(time.Second), err)
	}
	e.Log.Info("switch finished", "sha", sha, "duration", time.Since(started).Round(time.Second).String())
	return nil
}

// stream folds child output into the daemon's structured log so an unattended
// failure leaves a readable trace in the journal. The reader is always drained
// to EOF: a child blocked on a full pipe could never be reaped.
func (e *Exec) stream(r io.Reader, stream string) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		e.Log.Info("switch output", "stream", stream, "line", scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		e.Log.Warn("switch output truncated", "stream", stream, "error", err)
		io.Copy(io.Discard, r)
	}
}

// lockPollInterval bounds how long a cancellation waits behind a held lock.
const lockPollInterval = time.Second

// lock takes an exclusive advisory lock for the whole switch so two daemon
// cycles (or a daemon restart) cannot contend on the Nix store lock unnoticed.
// It is advisory: a manual nixos-rebuild does not take it. Waiting is
// non-blocking and polled so ctx cancellation and the switch timeout apply
// while queued behind another holder.
func lock(ctx context.Context, path string) (func(), error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open lock: %w", err)
	}
	for {
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) {
			f.Close()
			return nil, fmt.Errorf("lock %s: %w", path, err)
		}
		select {
		case <-ctx.Done():
			f.Close()
			return nil, fmt.Errorf("waiting for lock %s: %w", path, ctx.Err())
		case <-time.After(lockPollInterval):
		}
	}
	return func() {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}
