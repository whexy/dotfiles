package engine

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"dotfiles-upgraded/internal/announce"
	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
)

type fakeNotifier struct {
	pending []announce.Announcement
	healthy bool
	wake    chan struct{}
}

func (n *fakeNotifier) Wake() <-chan struct{} { return n.wake }
func (n *fakeNotifier) Healthy() bool         { return n.healthy }
func (n *fakeNotifier) Status() announce.Status {
	return announce.Status{Connected: n.healthy}
}
func (n *fakeNotifier) Take() (announce.Announcement, bool) {
	if len(n.pending) == 0 {
		return announce.Announcement{}, false
	}
	a := n.pending[0]
	n.pending = n.pending[1:]
	return a, true
}

// announcedEngine counts every GitHub request, whose tip is githubSha with a
// successful push status.
func announcedEngine(t *testing.T, githubSha string, st state.State) (*Engine, *rolloutSwitch, *rolloutStore, *fakeNotifier, *atomic.Int32) {
	t.Helper()
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.URL.Path == "/repos/whexy/dotfiles/commits/"+githubSha+"/status" {
			fmt.Fprint(w, `{"statuses":[{"context":"ci/woodpecker/push/woodpecker","state":"success"}]}`)
			return
		}
		fmt.Fprint(w, githubSha)
	}))
	t.Cleanup(server.Close)
	refs := github.New("whexy/dotfiles", "", server.Client())
	refs.BaseURL = server.URL
	sw := &rolloutSwitch{}
	store := &rolloutStore{st: st}
	notifier := &fakeNotifier{healthy: true, wake: make(chan struct{}, 1)}
	e := New(Config{Ref: "master", RequireCIPass: true, PollInterval: 10 * time.Minute, NotifiedPollInterval: 6 * time.Hour, MaxAttempts: 1},
		refs, sw, store, rolloutClock{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	e.Notifier = notifier
	return e, sw, store, notifier, &calls
}

const (
	shaA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	shaB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

func TestAnnouncementSwitchesWithoutGitHub(t *testing.T) {
	e, sw, store, notifier, calls := announcedEngine(t, shaA, state.State{LastSuccessSha: shaA, LastSeenSha: shaA, ETag: `"a"`})
	notifier.pending = []announce.Announcement{{Repo: "whexy/dotfiles", Ref: "master", Sha: shaB, Seq: 12}}

	wait := e.RunOnce(context.Background())

	if calls.Load() != 0 {
		t.Fatalf("GitHub requests = %d, want none", calls.Load())
	}
	if len(sw.shas) != 1 || sw.shas[0] != shaB {
		t.Fatalf("switches = %v, want [%s]", sw.shas, shaB)
	}
	if store.st.LastSuccessSha != shaB || store.st.AnnouncedSeq != 12 || store.st.ETag != "" {
		t.Fatalf("state = %+v", store.st)
	}
	if wait < 4*time.Hour {
		t.Fatalf("wait = %s, want the notified interval while healthy", wait)
	}
}

func TestReplayedAnnouncementIsIgnored(t *testing.T) {
	e, sw, _, notifier, calls := announcedEngine(t, shaA, state.State{LastSuccessSha: shaA, LastSeenSha: shaA, AnnouncedSeq: 12})
	notifier.pending = []announce.Announcement{
		{Repo: "whexy/dotfiles", Ref: "master", Sha: shaB, Seq: 12},
		{Repo: "whexy/dotfiles", Ref: "master", Sha: shaB, Seq: 11},
	}

	e.RunOnce(context.Background())
	e.RunOnce(context.Background())

	if len(sw.shas) != 0 {
		t.Fatalf("switched to a replayed announcement: %v", sw.shas)
	}
	if calls.Load() != 0 {
		t.Fatalf("GitHub requests = %d, want none", calls.Load())
	}
}

func TestAnnouncedIgnoredShaStaysIgnored(t *testing.T) {
	st := state.State{LastSuccessSha: shaA, LastSeenSha: shaB}
	st.Ignore(shaB, state.PhaseSwitchFailed)
	e, sw, _, notifier, _ := announcedEngine(t, shaA, st)
	notifier.pending = []announce.Announcement{{Repo: "whexy/dotfiles", Ref: "master", Sha: shaB, Seq: 3}}

	e.RunOnce(context.Background())

	if len(sw.shas) != 0 || e.phase != state.PhaseSwitchFailed {
		t.Fatalf("switches = %v, phase = %s", sw.shas, e.phase)
	}
}

func TestUnhealthyStreamPollsGitHub(t *testing.T) {
	e, sw, _, notifier, calls := announcedEngine(t, shaB, state.State{LastSuccessSha: shaA, LastSeenSha: shaA})
	notifier.healthy = false

	wait := e.RunOnce(context.Background())

	if calls.Load() == 0 || len(sw.shas) != 1 || sw.shas[0] != shaB {
		t.Fatalf("GitHub requests = %d, switches = %v; want the GitHub path", calls.Load(), sw.shas)
	}
	if wait > 15*time.Minute {
		t.Fatalf("wait = %s, want the plain poll interval while unhealthy", wait)
	}
}

// blockingClock sleeps until its context ends.
type blockingClock struct{}

func (blockingClock) Now() time.Time { return time.Unix(100, 0) }
func (blockingClock) Sleep(ctx context.Context, _ time.Duration) bool {
	<-ctx.Done()
	return false
}

func TestWakeEndsTheWait(t *testing.T) {
	e, _, _, notifier, _ := announcedEngine(t, shaA, state.State{})
	e.Clock = blockingClock{}
	notifier.wake <- struct{}{}

	done := make(chan bool)
	go func() { done <- e.wait(context.Background(), time.Hour) }()
	select {
	case ok := <-done:
		if !ok {
			t.Fatal("a wake read as the context ending")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the wake did not end the wait")
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if e.wait(ctx, time.Hour) {
		t.Fatal("an ended context read as a wake")
	}
}
