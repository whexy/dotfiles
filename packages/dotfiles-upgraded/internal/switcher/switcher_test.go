package switcher

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// The test binary re-executes itself as the rebuild command, so the exec path
// is covered without depending on a shell or any tool inside the Nix sandbox.
const fakeRebuildEnv = "DOTFILES_UPGRADED_FAKE_REBUILD"

func TestMain(m *testing.M) {
	switch os.Getenv(fakeRebuildEnv) {
	case "":
		os.Exit(m.Run())
	case "ok":
		fmt.Fprintln(os.Stdout, "building the system configuration")
		fmt.Fprintln(os.Stderr, "activating the configuration")
		os.Exit(0)
	case "fail":
		fmt.Fprintln(os.Stderr, "error: build of nixos-rebuild failed")
		os.Exit(1)
	case "hang":
		time.Sleep(time.Minute)
		os.Exit(0)
	case "spawn-hang":
		// Parent exits immediately after leaving a grandchild that inherits
		// stdout/stderr, mimicking nix or an activation script that outlives
		// the rebuild wrapper.
		child := exec.Command(os.Args[0])
		child.Env = append(os.Environ(), fakeRebuildEnv+"=hang")
		child.Stdout, child.Stderr = os.Stdout, os.Stderr
		if err := child.Start(); err != nil {
			os.Exit(2)
		}
		time.Sleep(time.Minute)
		os.Exit(0)
	case "flood":
		w := bufio.NewWriter(os.Stdout)
		w.WriteString(strings.Repeat("y", 2*1024*1024))
		w.WriteString("\n")
		for i := 0; i < 20000; i++ {
			w.WriteString("after the long line\n")
		}
		w.Flush()
		os.Exit(0)
	}
}

// fakeRebuild puts an executable named after the mode's command first on PATH.
func fakeRebuild(t *testing.T, behaviour string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.Symlink(os.Args[0], filepath.Join(dir, "nixos-rebuild")); err != nil {
		t.Fatalf("symlink fake rebuild: %v", err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv(fakeRebuildEnv, behaviour)
}

func TestParseMode(t *testing.T) {
	for _, name := range []string{"nixos", "darwin", "home-manager"} {
		if _, err := ParseMode(name); err != nil {
			t.Errorf("ParseMode(%q): %v", name, err)
		}
	}
	if _, err := ParseMode("linux"); err == nil {
		t.Error("expected an error for an unknown mode")
	}
	if _, err := ParseMode(""); err == nil {
		t.Error("expected an error for an empty mode")
	}
}

// The argv must match the replaced timers' commands except for the SHA pin.
func TestCommandPinsTheGatedSha(t *testing.T) {
	const sha = "0123456789abcdef0123456789abcdef01234567"
	tests := []struct {
		mode Mode
		cfg  string
		want []string
	}{
		{
			ModeNixOS, "mudd",
			[]string{"nixos-rebuild", "switch", "--refresh", "--flake", "github:whexy/dotfiles/" + sha + "#mudd"},
		},
		{
			ModeDarwin, "ellison",
			[]string{"darwin-rebuild", "switch", "--refresh", "--flake", "github:whexy/dotfiles/" + sha + "#ellison"},
		},
		{
			ModeHomeManager, "wenxuan@mars",
			[]string{"nh", "home", "switch", "github:whexy/dotfiles/" + sha, "--refresh", "--no-nom", "-c", "wenxuan@mars", "-b", "backup"},
		},
	}

	for _, tc := range tests {
		got := Command(tc.mode, "github:whexy/dotfiles", tc.cfg, sha)
		if !slices.Equal(got, tc.want) {
			t.Errorf("Command(%q) = %v, want %v", tc.mode, got, tc.want)
		}
	}

	if Command(Mode("bogus"), "flake", "cfg", sha) != nil {
		t.Error("expected nil argv for an unknown mode")
	}
}

func testExec(t *testing.T) (*Exec, *strings.Builder) {
	t.Helper()
	var logged strings.Builder
	return &Exec{
		Mode:          ModeNixOS,
		FlakeRef:      "github:whexy/dotfiles",
		Configuration: "test",
		LockPath:      filepath.Join(t.TempDir(), "lock"),
		Timeout:       30 * time.Second,
		Log:           slog.New(slog.NewTextHandler(&logged, nil)),
	}, &logged
}

func TestSwitchFailsWhenCommandIsMissing(t *testing.T) {
	e, _ := testExec(t)
	e.Mode = Mode("bogus")

	if err := e.Switch(context.Background(), "sha1"); err == nil {
		t.Fatal("expected an error for an unknown mode")
	}
}

func TestSwitchStreamsOutputAndSucceeds(t *testing.T) {
	fakeRebuild(t, "ok")
	e, logged := testExec(t)

	if err := e.Switch(context.Background(), "sha1"); err != nil {
		t.Fatalf("Switch: %v", err)
	}

	out := logged.String()
	for _, want := range []string{"building the system configuration", "activating the configuration", "switch finished"} {
		if !strings.Contains(out, want) {
			t.Errorf("log missing %q; got %s", want, out)
		}
	}
}

func TestSwitchReportsChildFailure(t *testing.T) {
	fakeRebuild(t, "fail")
	e, logged := testExec(t)

	err := e.Switch(context.Background(), "sha1")
	if err == nil {
		t.Fatal("expected an error when the rebuild exits non-zero")
	}
	if !strings.Contains(logged.String(), "build of nixos-rebuild failed") {
		t.Error("child stderr was not folded into the log")
	}
}

func TestSwitchFailsWhenTheCommandIsNotOnPath(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	e, _ := testExec(t)

	if err := e.Switch(context.Background(), "sha1"); err == nil {
		t.Fatal("expected an error when nixos-rebuild is absent")
	}
}

func TestSwitchTimesOut(t *testing.T) {
	fakeRebuild(t, "hang")
	e, _ := testExec(t)
	e.Timeout = 100 * time.Millisecond

	err := e.Switch(context.Background(), "sha1")
	if err == nil {
		t.Fatal("expected a timeout error")
	}
	if !strings.Contains(err.Error(), "timed out") {
		t.Errorf("error = %v, want a timeout", err)
	}
}

func TestSwitchReleasesTheLockAfterwards(t *testing.T) {
	fakeRebuild(t, "ok")
	e, _ := testExec(t)

	if err := e.Switch(context.Background(), "sha1"); err != nil {
		t.Fatalf("Switch: %v", err)
	}

	unlock, err := lock(context.Background(), e.LockPath)
	if err != nil {
		t.Fatalf("lock still held after Switch returned: %v", err)
	}
	unlock()
}

func TestLockIsExclusive(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lock")

	unlock, err := lock(context.Background(), path)
	if err != nil {
		t.Fatalf("first lock: %v", err)
	}

	acquired := make(chan struct{})
	go func() {
		secondUnlock, err := lock(context.Background(), path)
		if err == nil {
			secondUnlock()
		}
		close(acquired)
	}()

	select {
	case <-acquired:
		t.Fatal("second lock succeeded while the first was held")
	case <-time.After(200 * time.Millisecond):
	}

	unlock()
	select {
	case <-acquired:
	case <-time.After(5 * time.Second):
		t.Fatal("second lock did not acquire after release")
	}

	if _, err := os.Stat(path); err != nil {
		t.Errorf("lock file missing: %v", err)
	}
}

func TestLockFailsOnUnwritablePath(t *testing.T) {
	if _, err := lock(context.Background(), filepath.Join(t.TempDir(), "missing-dir", "lock")); err == nil {
		t.Fatal("expected an error when the lock directory does not exist")
	}
}

func TestStreamFoldsChildOutputIntoTheLog(t *testing.T) {
	e, logged := testExec(t)
	e.stream(strings.NewReader("building...\nactivating...\n"), "stdout")

	out := logged.String()
	for _, want := range []string{"building...", "activating...", "stream=stdout"} {
		if !strings.Contains(out, want) {
			t.Errorf("log missing %q; got %s", want, out)
		}
	}
}

func TestStreamHandlesLongLines(t *testing.T) {
	e, logged := testExec(t)
	long := strings.Repeat("x", 200*1024)
	e.stream(strings.NewReader(long+"\n"), "stderr")

	if logged.Len() == 0 {
		t.Fatal("long line produced no log output")
	}
}

func TestSwitchTimeoutKillsDescendantsHoldingThePipes(t *testing.T) {
	fakeRebuild(t, "spawn-hang")
	e, _ := testExec(t)
	e.Timeout = 200 * time.Millisecond

	returned := make(chan error, 1)
	go func() { returned <- e.Switch(context.Background(), "sha1") }()

	select {
	case err := <-returned:
		if err == nil || !strings.Contains(err.Error(), "timed out") {
			t.Errorf("error = %v, want a timeout", err)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("Switch did not return after the timeout; a descendant kept the pipes open")
	}
}

func TestSwitchDrainsOversizedOutput(t *testing.T) {
	fakeRebuild(t, "flood")
	e, logged := testExec(t)
	e.Timeout = 30 * time.Second

	if err := e.Switch(context.Background(), "sha1"); err != nil {
		t.Fatalf("Switch: %v", err)
	}
	if !strings.Contains(logged.String(), "truncated") {
		t.Error("expected the oversized line to be logged as truncated")
	}
}

func TestLockWaitHonoursCancellation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lock")
	unlock, err := lock(context.Background(), path)
	if err != nil {
		t.Fatalf("first lock: %v", err)
	}
	defer unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	start := time.Now()
	if _, err := lock(ctx, path); err == nil {
		t.Fatal("second lock succeeded while the first was held")
	} else if !strings.Contains(err.Error(), "waiting for lock") {
		t.Errorf("error = %v, want a lock-wait cancellation", err)
	}
	if time.Since(start) > 5*time.Second {
		t.Error("lock wait did not return promptly after cancellation")
	}
}
