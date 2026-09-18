package engine

import (
	"context"
	"errors"
	"testing"

	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
)

func TestExitAfterSwitchRecordsBeforeReturning(t *testing.T) {
	refs := &fakeRefs{heads: []refReply{ok("new", "etag")}, statuses: []statusReply{{state: github.StateSuccess}}}
	store := &memStore{}
	clock := &fakeClock{cancel: true}
	sw := &fakeSwitcher{}
	e := newEngine(t, refs, sw, store, clock)
	e.Config.ExitAfterSwitch = true
	e.Run(context.Background())
	if store.st.LastSuccessSha != "new" || store.status.LastSuccessSha != "new" || len(clock.slept) != 0 {
		t.Fatalf("must persist state and status before returning without sleep: state=%+v status=%+v sleeps=%v", store.st, store.status, clock.slept)
	}
}

func TestExitAfterSwitchDoesNotExitForUnchangedPendingOrFailed(t *testing.T) {
	for _, scenario := range []string{"unchanged", "pending", "failed"} {
		t.Run(scenario, func(t *testing.T) {
			refs := &fakeRefs{heads: []refReply{ok("new", "etag")}, statuses: []statusReply{{state: github.StateSuccess}}}
			store := &memStore{}
			sw := &fakeSwitcher{}
			switch scenario {
			case "unchanged":
				store.st = state.State{LastSuccessSha: "new"}
			case "pending":
				refs.statuses[0].state = github.StatePending
			case "failed":
				sw.results = []error{errors.New("activation failed")}
			}
			clock := &fakeClock{cancel: true}
			e := newEngine(t, refs, sw, store, clock)
			e.Config.ExitAfterSwitch = true
			e.Config.MaxAttempts = 1
			e.Run(context.Background())
			if len(clock.slept) != 1 {
				t.Fatalf("expected normal poll sleep, got %v", clock.slept)
			}
		})
	}
}
