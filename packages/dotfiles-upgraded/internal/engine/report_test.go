package engine

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
)

type outputErr struct{ lines []string }

func (outputErr) Error() string             { return "switch failed" }
func (e outputErr) RebuildOutput() []string { return e.lines }

type failingSwitch struct{ calls int }

func (s *failingSwitch) Switch(context.Context, string) error {
	s.calls++
	return outputErr{lines: []string{"error: builder failed", fmt.Sprintf("attempt %d", s.calls)}}
}

type permanentErr struct{}

func (permanentErr) Error() string   { return "rejected" }
func (permanentErr) Permanent() bool { return true }

type fakeReporter struct {
	errs []error
	got  []state.Failure
}

func (r *fakeReporter) Report(_ context.Context, f state.Failure) error {
	r.got = append(r.got, f)
	if len(r.errs) == 0 {
		return nil
	}
	err := r.errs[0]
	r.errs = r.errs[1:]
	return err
}

func failingEngine(t *testing.T, reporter *fakeReporter) (*Engine, *rolloutStore) {
	t.Helper()
	const sha = "1234567890123456789012345678901234567890"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/repos/whexy/dotfiles/commits/"+sha+"/status" {
			fmt.Fprint(w, `{"statuses":[{"context":"ci/woodpecker/push/woodpecker","state":"success"}]}`)
			return
		}
		fmt.Fprint(w, sha)
	}))
	t.Cleanup(server.Close)
	refs := github.New("whexy/dotfiles", "", server.Client())
	refs.BaseURL = server.URL
	store := &rolloutStore{}
	e := New(Config{Ref: "master", RequireCIPass: true, PollInterval: time.Minute, MaxAttempts: 1},
		refs, &failingSwitch{}, store, rolloutClock{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	e.Reporter = reporter
	return e, store
}

func TestGivingUpReportsOnceWithOutput(t *testing.T) {
	reporter := &fakeReporter{}
	e, store := failingEngine(t, reporter)

	e.RunOnce(context.Background())
	e.RunOnce(context.Background())

	if len(reporter.got) != 1 {
		t.Fatalf("reports = %d, want 1", len(reporter.got))
	}
	got := reporter.got[0]
	if got.Sha != "1234567890123456789012345678901234567890" || got.Attempts != 1 || got.Error != "switch failed" {
		t.Fatalf("report = %+v", got)
	}
	if len(got.Output) != 2 || got.Output[0] != "error: builder failed" {
		t.Fatalf("output = %q", got.Output)
	}
	if store.st.PendingFailure != nil {
		t.Fatal("delivered report stayed pending")
	}
}

func TestUndeliveredReportIsRetried(t *testing.T) {
	reporter := &fakeReporter{errs: []error{errors.New("offline")}}
	e, store := failingEngine(t, reporter)

	e.RunOnce(context.Background())
	if store.st.PendingFailure == nil {
		t.Fatal("undelivered report was not persisted")
	}
	e.RunOnce(context.Background())
	if len(reporter.got) != 2 || store.st.PendingFailure != nil {
		t.Fatalf("reports = %d, pending = %v; want a successful retry", len(reporter.got), store.st.PendingFailure)
	}
}

func TestRejectedReportIsDropped(t *testing.T) {
	reporter := &fakeReporter{errs: []error{permanentErr{}}}
	e, store := failingEngine(t, reporter)

	e.RunOnce(context.Background())
	e.RunOnce(context.Background())
	if len(reporter.got) != 1 || store.st.PendingFailure != nil {
		t.Fatalf("reports = %d, pending = %v; want one attempt, then dropped", len(reporter.got), store.st.PendingFailure)
	}
}
