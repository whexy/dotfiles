package engine

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
)

// fakeClock advances only when the engine sleeps, so tests run instantly and
// the backoff schedule is observable.
type fakeClock struct {
	now    time.Time
	slept  []time.Duration
	cancel bool
}

func (c *fakeClock) Now() time.Time { return c.now }

func (c *fakeClock) Sleep(ctx context.Context, d time.Duration) bool {
	c.slept = append(c.slept, d)
	c.now = c.now.Add(d)
	return !c.cancel && ctx.Err() == nil
}

type refReply struct {
	result github.RefResult
	err    error
}

type statusReply struct {
	state github.CIState
	err   error
}

// fakeRefs replays scripted API answers, repeating the last one so a test only
// scripts the cycles it cares about.
type fakeRefs struct {
	heads       []refReply
	statuses    []statusReply
	headCalls   int
	statusCalls int
	seenETags   []string
}

func (f *fakeRefs) Head(ctx context.Context, ref, etag string) (github.RefResult, error) {
	f.seenETags = append(f.seenETags, etag)
	reply := f.heads[min(f.headCalls, len(f.heads)-1)]
	f.headCalls++
	return reply.result, reply.err
}

func (f *fakeRefs) CombinedStatus(ctx context.Context, sha string) (github.CIState, error) {
	reply := f.statuses[min(f.statusCalls, len(f.statuses)-1)]
	f.statusCalls++
	return reply.state, reply.err
}

// fakeSwitcher records invocations; the engine must never shell out in tests.
type fakeSwitcher struct {
	results []error
	calls   []string
}

func (f *fakeSwitcher) Switch(ctx context.Context, sha string) error {
	f.calls = append(f.calls, sha)
	if len(f.results) == 0 {
		return nil
	}
	return f.results[min(len(f.calls)-1, len(f.results)-1)]
}

type memStore struct {
	st       state.State
	status   state.Status
	saves    int
	statuses int
}

func (m *memStore) Load() state.State { return m.st }

func (m *memStore) Save(st state.State) error {
	m.st = st
	m.saves++
	return nil
}

func (m *memStore) WriteStatus(st state.Status) error {
	m.status = st
	m.statuses++
	return nil
}

func ok(sha, etag string) refReply {
	return refReply{result: github.RefResult{SHA: sha, ETag: etag}}
}

func notModified() refReply {
	return refReply{result: github.RefResult{NotModified: true}}
}

func newEngine(t *testing.T, refs *fakeRefs, sw *fakeSwitcher, store *memStore, clock *fakeClock) *Engine {
	t.Helper()
	if store == nil {
		store = &memStore{}
	}
	if clock == nil {
		clock = &fakeClock{now: time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)}
	}
	cfg := Config{
		Ref:            "master",
		PollInterval:   10 * time.Minute,
		MaxAttempts:    3,
		RequireCIPass:  true,
		PendingTimeout: 2 * time.Hour,
		JitterSeed:     "test-host",
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	return New(cfg, refs, sw, store, clock, log)
}

func TestNewShaWithPassingCISwitchesAndRecords(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 1 || sw.calls[0] != "sha1" {
		t.Fatalf("switch calls = %v, want [sha1]", sw.calls)
	}
	if store.st.LastSuccessSha != "sha1" {
		t.Errorf("LastSuccessSha = %q, want sha1", store.st.LastSuccessSha)
	}
	if store.st.LastSuccessAt == nil {
		t.Error("LastSuccessAt not recorded")
	}
	if store.st.ETag != `W/"e1"` {
		t.Errorf("ETag = %q, want W/\"e1\"", store.st.ETag)
	}
	if store.status.ConsecutiveFailures != 0 || store.status.LastError != nil {
		t.Errorf("status reports a failure after success: %+v", store.status)
	}
}

func TestNotModifiedDoesNotSwitch(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{notModified()}}
	sw := &fakeSwitcher{}
	store := &memStore{st: state.State{ETag: `W/"e1"`, LastSuccessSha: "sha1", LastSeenSha: "sha1"}}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 0 {
		t.Fatalf("switch ran on a 304: %v", sw.calls)
	}
	if refs.seenETags[0] != `W/"e1"` {
		t.Errorf("stored ETag not sent: %v", refs.seenETags)
	}
	if refs.statusCalls != 0 {
		t.Error("CI status queried despite 304")
	}
}

func TestSameShaAsLastSuccessDoesNotSwitch(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{ok("sha1", `W/"e1"`)}}
	sw := &fakeSwitcher{}
	store := &memStore{st: state.State{LastSuccessSha: "sha1"}}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 0 {
		t.Fatalf("switch ran for an already-applied sha: %v", sw.calls)
	}
	if refs.statusCalls != 0 {
		t.Error("CI status queried for an already-applied sha")
	}
}

func TestCIPendingWaitsWithoutIgnoring(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StatePending}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 0 {
		t.Fatalf("switch ran while CI was pending: %v", sw.calls)
	}
	if len(store.st.IgnoredShas) != 0 {
		t.Errorf("pending CI must not ignore the sha: %v", store.st.IgnoredShas)
	}
}

func TestCIPendingTimesOutAndIgnores(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StatePending}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	clock := &fakeClock{now: time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)}
	e := newEngine(t, refs, sw, store, clock)

	e.RunOnce(context.Background())
	if len(store.st.IgnoredShas) != 0 {
		t.Fatalf("ignored too early: %v", store.st.IgnoredShas)
	}

	clock.now = clock.now.Add(3 * time.Hour)
	e.RunOnce(context.Background())

	if !store.st.Ignored("sha1") {
		t.Fatalf("sha not ignored after the pending timeout: %v", store.st.IgnoredShas)
	}
	if len(sw.calls) != 0 {
		t.Errorf("switch ran for a timed-out pending sha: %v", sw.calls)
	}
}

func TestCIFailureIgnoresShaImmediately(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StateFailure}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 0 {
		t.Fatalf("switch ran for a failing commit: %v", sw.calls)
	}
	if !store.st.Ignored("sha1") {
		t.Fatalf("failing sha not ignored: %v", store.st.IgnoredShas)
	}

	// A second cycle on the same SHA must not re-query CI.
	before := refs.statusCalls
	e.RunOnce(context.Background())
	if refs.statusCalls != before {
		t.Error("ignored sha was re-checked")
	}
	if len(sw.calls) != 0 {
		t.Errorf("ignored sha was switched to: %v", sw.calls)
	}
}

func TestSwitchRetriesThenIgnores(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{results: []error{errors.New("build failed")}}
	store := &memStore{}
	clock := &fakeClock{now: time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)}
	e := newEngine(t, refs, sw, store, clock)

	e.RunOnce(context.Background())

	if len(sw.calls) != 3 {
		t.Fatalf("switch attempted %d times, want 3 (--max-attempts)", len(sw.calls))
	}
	if !store.st.Ignored("sha1") {
		t.Fatalf("sha not ignored after exhausting retries: %v", store.st.IgnoredShas)
	}
	if store.st.LastSuccessSha != "" {
		t.Errorf("LastSuccessSha recorded despite failure: %q", store.st.LastSuccessSha)
	}
	if store.status.ConsecutiveFailures != 3 {
		t.Errorf("ConsecutiveFailures = %d, want 3", store.status.ConsecutiveFailures)
	}
	if store.status.LastError == nil {
		t.Error("LastError not populated after failures")
	}
	// Three attempts are separated by exactly two backoffs; the poll wait is
	// returned to the caller rather than slept inside the cycle.
	if len(clock.slept) != 2 {
		t.Fatalf("sleeps = %v, want two backoffs", clock.slept)
	}
	if clock.slept[0] != Backoff(1) || clock.slept[1] != Backoff(2) {
		t.Errorf("backoff schedule = %v, want %v then %v", clock.slept[:2], Backoff(1), Backoff(2))
	}
}

func TestSwitchSucceedsOnRetry(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`)},
		statuses: []statusReply{{state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{results: []error{errors.New("transient"), nil}}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 2 {
		t.Fatalf("switch attempted %d times, want 2", len(sw.calls))
	}
	if store.st.LastSuccessSha != "sha1" {
		t.Errorf("LastSuccessSha = %q, want sha1", store.st.LastSuccessSha)
	}
	if store.status.ConsecutiveFailures != 0 {
		t.Errorf("ConsecutiveFailures = %d, want 0 after eventual success", store.status.ConsecutiveFailures)
	}
}

func TestSuccessfulSwitchClearsIgnoreSet(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha2", `W/"e2"`)},
		statuses: []statusReply{{state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{st: state.State{IgnoredShas: []string{"sha1"}}}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(store.st.IgnoredShas) != 0 {
		t.Fatalf("ignore set survived a successful switch: %v", store.st.IgnoredShas)
	}
	if len(store.status.IgnoredShas) != 0 {
		t.Errorf("status still reports ignored shas: %v", store.status.IgnoredShas)
	}
}

func TestIgnoredShaSupersededByNewCommit(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`), ok("sha2", `W/"e2"`)},
		statuses: []statusReply{{state: github.StateFailure}, {state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())
	e.RunOnce(context.Background())

	if len(sw.calls) != 1 || sw.calls[0] != "sha2" {
		t.Fatalf("switch calls = %v, want [sha2]", sw.calls)
	}
	if store.st.LastSuccessSha != "sha2" {
		t.Errorf("LastSuccessSha = %q, want sha2", store.st.LastSuccessSha)
	}
}

func TestRequireCIPassDisabledSkipsStatusCheck(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{ok("sha1", `W/"e1"`)}}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)
	e.Config.RequireCIPass = false

	e.RunOnce(context.Background())

	if refs.statusCalls != 0 {
		t.Error("CI status queried with --require-ci-pass=false")
	}
	if len(sw.calls) != 1 {
		t.Fatalf("switch calls = %v, want one", sw.calls)
	}
}

func TestRateLimitBackoffUsesRetryAfter(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{{err: &github.RateLimitError{StatusCode: 429, RetryAfter: 7 * time.Minute}}}}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	wait := e.RunOnce(context.Background())

	if wait != 7*time.Minute {
		t.Errorf("wait = %v, want the server's 7m hint", wait)
	}
	if store.status.ConsecutiveFailures != 1 || store.status.LastError == nil {
		t.Errorf("rate limit not surfaced in status: %+v", store.status)
	}
}

func TestRateLimitWithoutHintUsesFallback(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{{err: &github.RateLimitError{StatusCode: 403}}}}
	e := newEngine(t, refs, &fakeSwitcher{}, nil, nil)

	if wait := e.RunOnce(context.Background()); wait != rateLimitFallback {
		t.Errorf("wait = %v, want the %v fallback", wait, rateLimitFallback)
	}
}

func TestServerPollIntervalRaisesTheFloor(t *testing.T) {
	refs := &fakeRefs{
		heads: []refReply{{result: github.RefResult{
			NotModified:  true,
			PollInterval: time.Hour,
		}}},
	}
	e := newEngine(t, refs, &fakeSwitcher{}, nil, nil)

	wait := e.RunOnce(context.Background())

	if wait < time.Hour {
		t.Errorf("wait = %v, want at least the server-requested hour", wait)
	}
	// Jitter must never dip under the floor, whatever the tick hashes to.
	for i := 0; i < 200; i++ {
		e.Clock.(*fakeClock).now = e.Clock.(*fakeClock).now.Add(time.Minute)
		if got := e.nextInterval(); got < time.Hour {
			t.Fatalf("tick %d: wait = %v, below the server floor", i, got)
		}
	}
}

func TestNotModifiedKeepsGatingThePendingCandidate(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha2", `W/"e2"`), notModified()},
		statuses: []statusReply{{state: github.StatePending}, {state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{st: state.State{LastSuccessSha: "sha1"}}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())
	if len(sw.calls) != 0 {
		t.Fatalf("switched while pending: %v", sw.calls)
	}
	e.RunOnce(context.Background())

	if refs.seenETags[1] != `W/"e2"` {
		t.Errorf("second poll sent ETag %q, want the persisted one", refs.seenETags[1])
	}
	if len(sw.calls) != 1 || sw.calls[0] != "sha2" {
		t.Fatalf("304 stranded the pending candidate; switch calls = %v", sw.calls)
	}
	if store.st.LastSuccessSha != "sha2" {
		t.Errorf("lastSuccessSha = %q, want sha2", store.st.LastSuccessSha)
	}
}

func TestRestartAfterInterruptedSwitchRetriesOn304(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{notModified()},
		statuses: []statusReply{{state: github.StateSuccess}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{st: state.State{ETag: `W/"e2"`, LastSeenSha: "sha2", LastSuccessSha: "sha1"}}
	e := newEngine(t, refs, sw, store, nil)

	e.RunOnce(context.Background())

	if len(sw.calls) != 1 || sw.calls[0] != "sha2" {
		t.Fatalf("seen-but-unapplied sha not retried after restart; calls = %v", sw.calls)
	}
}

func TestNewHeadResetsThePendingClock(t *testing.T) {
	refs := &fakeRefs{
		heads:    []refReply{ok("sha1", `W/"e1"`), ok("sha2", `W/"e2"`)},
		statuses: []statusReply{{state: github.StatePending}},
	}
	sw := &fakeSwitcher{}
	store := &memStore{}
	clock := &fakeClock{now: time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)}
	e := newEngine(t, refs, sw, store, clock)

	e.RunOnce(context.Background())
	clock.now = clock.now.Add(3 * time.Hour)
	e.RunOnce(context.Background())

	if len(e.pendingSince) != 1 {
		t.Errorf("pendingSince holds %d entries, want only the current head", len(e.pendingSince))
	}
	if _, stale := e.pendingSince["sha1"]; stale {
		t.Error("superseded sha1 still tracked")
	}
}

func TestNetworkErrorIsRecordedAndRetried(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{{err: errors.New("dns failure")}}}
	sw := &fakeSwitcher{}
	store := &memStore{}
	e := newEngine(t, refs, sw, store, nil)

	wait := e.RunOnce(context.Background())

	if len(sw.calls) != 0 {
		t.Fatal("switch ran despite a failed ref lookup")
	}
	if store.status.ConsecutiveFailures != 1 {
		t.Errorf("ConsecutiveFailures = %d, want 1", store.status.ConsecutiveFailures)
	}
	if wait <= 0 {
		t.Errorf("wait = %v, want a positive poll interval", wait)
	}
}

func TestBackoffScheduleBounds(t *testing.T) {
	if got := Backoff(1); got != backoffBase {
		t.Errorf("Backoff(1) = %v, want %v", got, backoffBase)
	}
	if got := Backoff(2); got != 2*backoffBase {
		t.Errorf("Backoff(2) = %v, want %v", got, 2*backoffBase)
	}
	if got := Backoff(3); got != 4*backoffBase {
		t.Errorf("Backoff(3) = %v, want %v", got, 4*backoffBase)
	}

	// The schedule must be monotonic and never exceed the cap.
	prev := time.Duration(0)
	for attempt := 1; attempt <= 20; attempt++ {
		got := Backoff(attempt)
		if got < prev {
			t.Fatalf("Backoff(%d) = %v decreased from %v", attempt, got, prev)
		}
		if got > backoffMax {
			t.Fatalf("Backoff(%d) = %v exceeds the %v cap", attempt, got, backoffMax)
		}
		prev = got
	}
	if Backoff(20) != backoffMax {
		t.Errorf("Backoff(20) = %v, want the %v cap", Backoff(20), backoffMax)
	}
}

func TestJitterStaysWithinBoundsAndVariesByHost(t *testing.T) {
	base := 10 * time.Minute
	now := time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)
	low := time.Duration(float64(base) * (1 - jitterFraction))
	high := time.Duration(float64(base) * (1 + jitterFraction))

	for i := 0; i < 500; i++ {
		got := jitter(base, "host-a", now.Add(time.Duration(i)*time.Second))
		if got < low || got > high {
			t.Fatalf("jitter = %v, outside [%v, %v]", got, low, high)
		}
	}

	differs := false
	for i := 0; i < 50; i++ {
		at := now.Add(time.Duration(i) * time.Second)
		if jitter(base, "host-a", at) != jitter(base, "host-b", at) {
			differs = true
			break
		}
	}
	if !differs {
		t.Error("jitter is identical across hosts, which defeats its purpose")
	}
}

func TestRunStopsWhenContextIsCancelled(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{notModified()}}
	clock := &fakeClock{now: time.Now(), cancel: true}
	e := newEngine(t, refs, &fakeSwitcher{}, nil, clock)

	done := make(chan struct{})
	go func() {
		e.Run(context.Background())
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return when the clock reported cancellation")
	}
}

func TestStatusIsWrittenEveryCycle(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{notModified()}}
	store := &memStore{}
	e := newEngine(t, refs, &fakeSwitcher{}, store, nil)

	e.RunOnce(context.Background())
	e.RunOnce(context.Background())

	if store.statuses != 2 {
		t.Errorf("status written %d times, want once per cycle", store.statuses)
	}
	if store.status.LastCheck.IsZero() {
		t.Error("LastCheck not set")
	}
}
