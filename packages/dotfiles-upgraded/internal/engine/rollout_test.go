package engine

import (
	"context"
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

type rolloutStore struct{ st state.State }

func (s *rolloutStore) Load() state.State            { return s.st }
func (s *rolloutStore) Save(st state.State) error    { s.st = st; return nil }
func (*rolloutStore) WriteStatus(state.Status) error { return nil }

type rolloutClock struct{}

func (rolloutClock) Now() time.Time                            { return time.Unix(100, 0) }
func (rolloutClock) Sleep(context.Context, time.Duration) bool { return false }

type rolloutSwitch struct{ shas []string }

func (s *rolloutSwitch) Switch(_ context.Context, sha string) error {
	s.shas = append(s.shas, sha)
	return nil
}

func TestBotRolloutRequiresSuccessfulPush(t *testing.T) {
	const sha = "1234567890123456789012345678901234567890"
	for _, verdict := range []string{"success", "failure", "error", "pending"} {
		t.Run(verdict, func(t *testing.T) {
			statuses := `{"statuses":[{"context":"ci/woodpecker/cron/check","state":"success"}]}`
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/repos/whexy/dotfiles/commits/"+sha+"/status" {
					fmt.Fprint(w, statuses)
					return
				}
				fmt.Fprint(w, sha)
			}))
			defer server.Close()
			refs := github.New("whexy/dotfiles", "", server.Client())
			refs.BaseURL = server.URL
			sw := &rolloutSwitch{}
			store := &rolloutStore{}
			e := New(Config{Ref: "master", RequireCIPass: true, PollInterval: time.Minute}, refs, sw, store, rolloutClock{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
			e.RunOnce(context.Background())
			if len(sw.shas) != 0 {
				t.Fatal("cron status allowed rollout without push status")
			}
			statuses = fmt.Sprintf(`{"statuses":[{"context":"ci/woodpecker/push/check","state":%q}]}`, verdict)
			e.RunOnce(context.Background())
			if got, want := len(sw.shas), map[bool]int{true: 1, false: 0}[verdict == "success"]; got != want {
				t.Fatalf("switches = %d, want %d", got, want)
			}
			if verdict == "success" && store.st.LastSuccessSha != sha {
				t.Fatal("same bot commit was not adopted")
			}
		})
	}
}
