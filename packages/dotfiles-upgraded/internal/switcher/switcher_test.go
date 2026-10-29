package switcher

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestRebuildFixture(t *testing.T) {
	mode := os.Getenv("SWITCHER_FIXTURE")
	if mode == "" {
		return
	}
	if mode == "stopped" {
		if mode != "graceful" {
			signal.Ignore(syscall.SIGTERM)
		}
		if err := os.WriteFile(os.Getenv("SWITCHER_PID"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
			os.Exit(2)
		}
		os.Stdout.Close()
		os.Stderr.Close()
		_ = syscall.Kill(os.Getpid(), syscall.SIGSTOP)
		for {
			time.Sleep(time.Hour)
		}
	}
	if os.Getenv("SWITCHER_CHILD") == "1" {
		if mode != "graceful" {
			signal.Ignore(syscall.SIGTERM)
		}
		if mode == "close-pipes" {
			go func() {
				time.Sleep(3 * time.Second)
				os.Stdout.Close()
				os.Stderr.Close()
			}()
		}
		if err := os.WriteFile(os.Getenv("SWITCHER_PID"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
			os.Exit(2)
		}
		for {
			time.Sleep(time.Hour)
		}
	}
	if mode == "normal" {
		for i := 0; i < 5000; i++ {
			fmt.Printf("out-%d\n", i)
			fmt.Fprintf(os.Stderr, "err-%d\n", i)
		}
		os.Exit(0)
	}
	if mode != "graceful" {
		signal.Ignore(syscall.SIGTERM)
	}
	child := exec.Command(os.Args[0], "-test.run=^TestRebuildFixture$")
	child.Env = append(os.Environ(), "SWITCHER_CHILD=1")
	if mode == "escaped" {
		child.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	}
	child.Stdout, child.Stderr = os.Stdout, os.Stderr
	if err := child.Start(); err != nil {
		os.Exit(2)
	}
	for {
		if _, err := os.Stat(os.Getenv("SWITCHER_PID")); err == nil {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if mode == "orphan" || mode == "close-pipes" || mode == "escaped" {
		os.Exit(0)
	}
	_ = child.Wait()
	os.Exit(0)
}

func fixtureExec(t *testing.T, mode string, output *bytes.Buffer) *Exec {
	t.Helper()
	dir := t.TempDir()
	binary, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	// The fake rebuild runs only this test binary; no live host command is used.
	shell, err := exec.LookPath("sh")
	if err != nil {
		t.Fatal(err)
	}
	script := "#!" + shell + "\nexec '" + strings.ReplaceAll(binary, "'", "'\\''") + "' -test.run=^TestRebuildFixture$\n"
	if err := os.WriteFile(filepath.Join(dir, "nixos-rebuild"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("SWITCHER_FIXTURE", mode)
	t.Setenv("SWITCHER_PID", filepath.Join(dir, "child.pid"))
	return &Exec{Mode: ModeNixOS, FlakeRef: "fixture", Configuration: "fixture", LockPath: filepath.Join(dir, "lock"), Log: slog.New(slog.NewTextHandler(output, nil))}
}

func TestNormalOutputCollection(t *testing.T) {
	var output bytes.Buffer
	e := fixtureExec(t, "normal", &output)
	e.Timeout = 10 * time.Second
	if err := e.Switch(context.Background(), "sha"); err != nil {
		t.Fatal(err)
	}
	for _, stream := range []string{"out", "err"} {
		for i := 0; i < 5000; i++ {
			if !strings.Contains(output.String(), fmt.Sprintf("line=%s-%d\n", stream, i)) {
				t.Fatalf("missing %s-%d", stream, i)
			}
		}
	}
}

func TestTimeoutKillsProcessGroupAndReleasesLock(t *testing.T) {
	for _, mode := range []string{"stubborn", "orphan", "close-pipes", "escaped", "graceful", "stopped"} {
		t.Run(mode, func(t *testing.T) {
			var output bytes.Buffer
			e := fixtureExec(t, mode, &output)
			e.Timeout = 2 * time.Second
			// This process is outside the rebuild's group and must survive cancellation.
			unrelated := exec.Command("sleep", "60")
			if err := unrelated.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = unrelated.Process.Kill(); _ = unrelated.Wait() }()
			started := time.Now()
			switchErr := e.Switch(context.Background(), "sha")
			raw, err := os.ReadFile(os.Getenv("SWITCHER_PID"))
			if err != nil {
				t.Fatal(err)
			}
			pid, err := strconv.Atoi(string(raw))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
			if !errors.Is(switchErr, context.DeadlineExceeded) {
				t.Fatalf("got %v, want deadline error", switchErr)
			}
			if elapsed := time.Since(started); elapsed > e.Timeout+terminationGrace+3*time.Second {
				t.Fatalf("timeout took %s", elapsed)
			}
			if mode == "graceful" && time.Since(started) < e.Timeout+terminationGrace {
				t.Fatal("cancellation skipped the fixed grace")
			}
			if mode == "escaped" {
				if !processRunning(pid) {
					t.Fatal("escaped process was signaled outside the rebuild group")
				}
			} else {
				deadline := time.Now().Add(2 * time.Second)
				for processRunning(pid) {
					if time.Now().After(deadline) {
						t.Fatalf("descendant %d survived", pid)
					}
					time.Sleep(10 * time.Millisecond)
				}
			}
			if err := unrelated.Process.Signal(syscall.Signal(0)); err != nil {
				t.Fatalf("unrelated process was killed: %v", err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			unlock, err := lock(ctx, e.LockPath)
			if err != nil {
				t.Fatalf("lock retained: %v", err)
			}
			unlock()
		})
	}
}

func processRunning(pid int) bool {
	if err := syscall.Kill(pid, 0); errors.Is(err, syscall.ESRCH) {
		return false
	}
	// A killed orphan can remain a zombie until the container's PID 1 reaps it.
	if stat, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid)); err == nil {
		if end := strings.LastIndex(string(stat), ") "); end >= 0 && strings.HasPrefix(string(stat)[end+2:], "Z ") {
			return false
		}
	}
	return true
}

func TestCanceledContextDoesNotStartRebuild(t *testing.T) {
	var output bytes.Buffer
	e := fixtureExec(t, "stubborn", &output)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := e.Switch(ctx, "sha"); !errors.Is(err, context.Canceled) {
		t.Fatalf("got %v, want cancellation", err)
	}
	if _, err := os.Stat(os.Getenv("SWITCHER_PID")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("rebuild started with canceled context: %v", err)
	}
}

func TestWaitForExitDoesNotReapLeader(t *testing.T) {
	cmd := exec.Command("sh", "-c", "exit 7")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = cmd.Process.Kill(); _ = cmd.Wait() }()
	if err := waitForExit(cmd.Process.Pid); err != nil {
		t.Fatal(err)
	}
	if err := cmd.Wait(); err == nil || cmd.ProcessState == nil || cmd.ProcessState.ExitCode() != 7 {
		t.Fatalf("leader was reaped before final Wait: %v", err)
	}
}

func TestCallerCancellationKillsGroup(t *testing.T) {
	var output bytes.Buffer
	e := fixtureExec(t, "stubborn", &output)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- e.Switch(ctx, "sha") }()
	readiness := time.NewTimer(10 * time.Second)
	defer readiness.Stop()
	var pid int
	for pid == 0 {
		if raw, err := os.ReadFile(os.Getenv("SWITCHER_PID")); err == nil {
			pid, _ = strconv.Atoi(string(raw))
		}
		select {
		case err := <-done:
			t.Fatalf("switch ended before cancellation: %v", err)
		case <-readiness.C:
			t.Fatal("fixture did not become ready")
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}
	t.Cleanup(func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("got %v, want caller cancellation", err)
		}
	case <-time.After(terminationGrace + 3*time.Second):
		t.Fatal("caller cancellation did not return")
	}
	if processRunning(pid) {
		t.Fatal("descendant survived caller cancellation")
	}
	unlock, err := lock(context.Background(), e.LockPath)
	if err != nil {
		t.Fatal(err)
	}
	unlock()
}

func TestWaitForExitRejectsNonChild(t *testing.T) {
	if err := waitForExit(1 << 30); !errors.Is(err, syscall.ECHILD) {
		t.Fatalf("got %v, want ECHILD", err)
	}
}
