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
	"strings"
	"sync"
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
	observeExit   func(int) error
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

	cmd := exec.Command(argv[0], argv[1:]...)
	// A rebuild forks nix and activation scripts; killing only the direct
	// child would leave them running (and holding our pipes), so the whole
	// process group is signalled on cancellation.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// Own the pipes: exec.Cmd.Wait must reap the leader without closing output
	// that its descendants are still writing.
	stdout, stdoutWriter, err := os.Pipe()
	if err != nil {
		return err
	}
	defer stdout.Close()
	defer stdoutWriter.Close()
	stderr, stderrWriter, err := os.Pipe()
	if err != nil {
		return err
	}
	defer stderr.Close()
	defer stderrWriter.Close()
	cmd.Stdout, cmd.Stderr = stdoutWriter, stderrWriter

	if err := ctx.Err(); err != nil {
		return err
	}
	e.Log.Info("switch starting", "sha", sha, "command", argv)
	started := time.Now()
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start %s: %w", argv[0], err)
	}

	stdoutWriter.Close()
	stderrWriter.Close()
	output := &tail{}
	outputDone := make(chan struct{})
	go func() {
		done := make(chan struct{}, 2)
		go func() { e.stream(stdout, "stdout", output); done <- struct{}{} }()
		go func() { e.stream(stderr, "stderr", output); done <- struct{}{} }()
		<-done
		<-done
		close(outputDone)
	}()
	waitDone := make(chan error, 1)
	observeExit := e.observeExit
	if observeExit == nil {
		observeExit = waitForExit
	}
	go func() { waitDone <- observeExit(cmd.Process.Pid) }()

	// Keep cancellation active until both the leader and its output finish.
	// A leader can exit while a descendant keeps the pipes and group alive.
	// Cancellation always runs the full grace: EOF does not prove that every
	// descendant exited, and the reserved zombie leader keeps the group present.
	ctxDone := ctx.Done()
	var grace <-chan time.Time
	var timer *time.Timer
	defer func() {
		if timer != nil {
			timer.Stop()
		}
	}()
	var cancelErr error
	startCancellation := func(err error) {
		cancelErr = err
		ctxDone = nil
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		timer = time.NewTimer(terminationGrace)
		grace = timer.C
	}
	for waitDone != nil || outputDone != nil || grace != nil {
		select {
		case exitErr := <-waitDone:
			waitDone = nil
			if errors.Is(exitErr, syscall.ECHILD) {
				// Another reaper invalidated PID ownership; further group signals
				// could reach a recycled ID, so only our pipe handles are closed.
				if cancelErr == nil {
					cancelErr = fmt.Errorf("observe rebuild exit: %w", exitErr)
				}
				ctxDone = nil
				if timer != nil {
					timer.Stop()
				}
				grace = nil
				stdout.Close()
				stderr.Close()
			} else if exitErr != nil && cancelErr == nil {
				startCancellation(fmt.Errorf("observe rebuild exit: %w", exitErr))
			}
		case <-outputDone:
			outputDone = nil
		case <-ctxDone:
			startCancellation(ctx.Err())
		case <-grace:
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			// An escaped descendant must not retain the daemon's readers.
			stdout.Close()
			stderr.Close()
			grace = nil
		}

	}
	// Reap only after the last possible group signal. The unreaped leader
	// reserves its PID even if every pipe holder escaped the process group.
	waitErr := cmd.Wait()
	if cancelErr != nil {
		if errors.Is(cancelErr, context.DeadlineExceeded) {
			cancelErr = fmt.Errorf("switch timed out after %s: %w", e.Timeout, cancelErr)
		}
		return &OutputError{Err: cancelErr, Output: output.snapshot()}
	}
	if waitErr != nil {
		return &OutputError{
			Err:    fmt.Errorf("switch failed after %s: %w", time.Since(started).Round(time.Second), waitErr),
			Output: output.snapshot(),
		}
	}

	e.Log.Info("switch finished", "sha", sha, "duration", time.Since(started).Round(time.Second).String())
	return nil
}

// stream folds child output into the daemon's structured log so an unattended
// failure leaves a readable trace in the journal. The reader is always drained
// to EOF: a child blocked on a full pipe could never be reaped.
func (e *Exec) stream(r io.Reader, stream string, output *tail) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		e.Log.Info("switch output", "stream", stream, "line", scanner.Text())
		output.add(scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		e.Log.Warn("switch output truncated", "stream", stream, "error", err)
		io.Copy(io.Discard, r)
	}
}

// OutputError is a rebuild that ran and failed, with the end of what it
// printed.
type OutputError struct {
	Err    error
	Output []string
}

func (e *OutputError) Error() string { return e.Err.Error() }
func (e *OutputError) Unwrap() error { return e.Err }

// RebuildOutput returns the last lines the rebuild printed.
func (e *OutputError) RebuildOutput() []string { return e.Output }

const (
	// Nix prints a failed build's log tail and the error itself last, so the
	// end of the output is enough to diagnose a failure.
	tailLines = 40
	// tailLineBytes keeps a single runaway line from crowding out the rest.
	tailLineBytes = 512
)

// tail keeps the last lines of a rebuild's interleaved stdout and stderr.
type tail struct {
	mu    sync.Mutex
	lines []string
}

func (t *tail) add(line string) {
	if len(line) > tailLineBytes {
		line = strings.ToValidUTF8(line[:tailLineBytes], "") + "…"
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	t.lines = append(t.lines, line)
	if len(t.lines) > tailLines {
		t.lines = t.lines[len(t.lines)-tailLines:]
	}
}

func (t *tail) snapshot() []string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return append([]string(nil), t.lines...)
}

// terminationGrace lets activation scripts exit before killing the rebuild group.
const terminationGrace = 10 * time.Second

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
