package github

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

const tipSHA = "4d79fa781db28881eedfdf07baad62e8c32a00c5"

func newTestClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	c := New("whexy/dotfiles", "", srv.Client())
	c.BaseURL = srv.URL
	return c
}

func TestHeadSendsRequiredHeaders(t *testing.T) {
	var got http.Header
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		got = r.Header.Clone()
		w.Header().Set("ETag", `W/"v1"`)
		w.Write([]byte(tipSHA))
	})

	if _, err := c.Head(context.Background(), "master", ""); err != nil {
		t.Fatalf("Head: %v", err)
	}
	if got.Get("Accept") != "application/vnd.github.sha" {
		t.Errorf("Accept = %q", got.Get("Accept"))
	}
	if got.Get("X-GitHub-Api-Version") != apiVersion {
		t.Errorf("X-GitHub-Api-Version = %q", got.Get("X-GitHub-Api-Version"))
	}
	if got.Get("User-Agent") != userAgent {
		t.Errorf("User-Agent = %q", got.Get("User-Agent"))
	}
	if _, ok := got["Authorization"]; ok {
		t.Error("unauthenticated client must not send Authorization")
	}
}

func TestHeadSendsBearerTokenWhenPresent(t *testing.T) {
	var auth string
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		w.Write([]byte(tipSHA))
	})
	c.Token = "secret"

	if _, err := c.Head(context.Background(), "master", ""); err != nil {
		t.Fatalf("Head: %v", err)
	}
	if auth != "Bearer secret" {
		t.Errorf("Authorization = %q", auth)
	}
}

func TestHeadConditionalGet(t *testing.T) {
	const etag = `W/"v1"`
	var sawIfNoneMatch string
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		sawIfNoneMatch = r.Header.Get("If-None-Match")
		if sawIfNoneMatch == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", etag)
		w.Write([]byte(tipSHA))
	})

	first, err := c.Head(context.Background(), "master", "")
	if err != nil {
		t.Fatalf("first Head: %v", err)
	}
	if first.NotModified {
		t.Fatal("first request should not be a 304")
	}
	if first.SHA != tipSHA {
		t.Errorf("SHA = %q", first.SHA)
	}
	if first.ETag != etag {
		t.Errorf("ETag = %q, want %q", first.ETag, etag)
	}

	second, err := c.Head(context.Background(), "master", first.ETag)
	if err != nil {
		t.Fatalf("second Head: %v", err)
	}
	if sawIfNoneMatch != etag {
		t.Errorf("If-None-Match = %q, want %q", sawIfNoneMatch, etag)
	}
	if !second.NotModified {
		t.Fatal("expected 304 for unchanged ref")
	}
	// A 304 carries no body, so the caller must keep the previous ETag.
	if second.ETag != etag {
		t.Errorf("ETag after 304 = %q, want %q", second.ETag, etag)
	}
}

// GitHub's full commit JSON carries every file's patch, so it grows with the
// diff; only the sha media type keeps the response a fixed size.
func TestHeadReadsTheTipOfAHugeCommit(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Accept") == "application/vnd.github.sha" {
			w.Header().Set("ETag", `"`+tipSHA+`"`)
			w.Write([]byte(tipSHA))
			return
		}
		type file struct {
			Patch string `json:"patch"`
		}
		w.Header().Set("ETag", `W/"full"`)
		json.NewEncoder(w).Encode(struct {
			SHA   string `json:"sha"`
			Files []file `json:"files"`
		}{tipSHA, []file{{Patch: strings.Repeat("+", 2*maxBody)}}})
	})

	res, err := c.Head(context.Background(), "master", "")
	if err != nil {
		t.Fatalf("Head: %v", err)
	}
	if res.SHA != tipSHA {
		t.Errorf("SHA = %q, want %q", res.SHA, tipSHA)
	}
	if res.ETag != `"`+tipSHA+`"` {
		t.Errorf("ETag = %q, want the sha representation's", res.ETag)
	}
}

func TestHeadAcceptsSHA256AndTrailingWhitespace(t *testing.T) {
	sha256 := strings.Repeat("0123456789abcdef", 4)
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(sha256 + "\n"))
	})

	res, err := c.Head(context.Background(), "master", "")
	if err != nil {
		t.Fatalf("Head: %v", err)
	}
	if res.SHA != sha256 {
		t.Errorf("SHA = %q, want %q", res.SHA, sha256)
	}
}

// The SHA is interpolated into the flake ref and API paths, so a 200 that is
// not a bare object name must fail rather than become a switch target.
func TestHeadRejectsABodyThatIsNotASHA(t *testing.T) {
	for name, body := range map[string]string{
		"empty":            "",
		"html":             "<html><body>captive portal</body></html>",
		"json":             `{"sha":"` + tipSHA + `"}`,
		"abbreviated":      "4d79fa7",
		"uppercase":        strings.ToUpper(tipSHA),
		"non-hex":          strings.Repeat("g", 40),
		"path traversal":   "../../../../etc/passwd/aaaaaaaaaaaaaaaaa",
		"sha with garbage": tipSHA + "#evil",
	} {
		t.Run(name, func(t *testing.T) {
			c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
				w.Write([]byte(body))
			})

			if res, err := c.Head(context.Background(), "master", ""); err == nil {
				t.Fatalf("accepted %q as SHA %q", body, res.SHA)
			}
		})
	}
}

func TestHeadHonoursPollInterval(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Poll-Interval", "120")
		w.Write([]byte(tipSHA))
	})

	res, err := c.Head(context.Background(), "master", "")
	if err != nil {
		t.Fatalf("Head: %v", err)
	}
	if res.PollInterval != 2*time.Minute {
		t.Errorf("PollInterval = %v, want 2m", res.PollInterval)
	}
}

func TestHeadRateLimitRetryAfter(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "60")
		w.WriteHeader(http.StatusTooManyRequests)
	})

	_, err := c.Head(context.Background(), "master", "")
	var rl *RateLimitError
	if !errors.As(err, &rl) {
		t.Fatalf("expected RateLimitError, got %v", err)
	}
	if rl.StatusCode != http.StatusTooManyRequests {
		t.Errorf("StatusCode = %d", rl.StatusCode)
	}
	if rl.RetryAfter != time.Minute {
		t.Errorf("RetryAfter = %v, want 1m", rl.RetryAfter)
	}
}

// An unauthenticated client shares a per-IP budget, so the 403 form of the
// rate limit must produce the same wait hint as the 429 form.
func TestHeadRateLimitResetHeader(t *testing.T) {
	now := time.Date(2026, 9, 17, 4, 0, 0, 0, time.UTC)
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-RateLimit-Remaining", "0")
		w.Header().Set("X-RateLimit-Reset", strconv.FormatInt(now.Add(5*time.Minute).Unix(), 10))
		w.WriteHeader(http.StatusForbidden)
	})
	c.Now = func() time.Time { return now }

	_, err := c.Head(context.Background(), "master", "")
	var rl *RateLimitError
	if !errors.As(err, &rl) {
		t.Fatalf("expected RateLimitError, got %v", err)
	}
	if rl.RetryAfter != 5*time.Minute {
		t.Errorf("RetryAfter = %v, want 5m", rl.RetryAfter)
	}
}

func TestHeadRateLimitWithoutHint(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	})

	_, err := c.Head(context.Background(), "master", "")
	var rl *RateLimitError
	if !errors.As(err, &rl) {
		t.Fatalf("expected RateLimitError, got %v", err)
	}
	if rl.RetryAfter != 0 {
		t.Errorf("RetryAfter = %v, want 0 so the caller applies its own fallback", rl.RetryAfter)
	}
}

func TestHeadUnexpectedStatus(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})

	if _, err := c.Head(context.Background(), "master", ""); err == nil {
		t.Fatal("expected an error for HTTP 404")
	}
}

// combined renders a combined-status body. The top-level state folds in every
// lane, as GitHub computes it, so a test passing only on that field would not
// exercise the per-lane gate.
func combined(statuses ...[2]string) string {
	type status struct {
		Context string `json:"context"`
		State   string `json:"state"`
	}
	body := struct {
		State    string   `json:"state"`
		Statuses []status `json:"statuses"`
	}{State: "success", Statuses: []status{}}
	for _, s := range statuses {
		body.Statuses = append(body.Statuses, status{Context: s[0], State: s[1]})
		switch s[1] {
		case "success":
		case "failure", "error":
			body.State = "failure"
		default:
			if body.State != "failure" {
				body.State = "pending"
			}
		}
	}
	raw, err := json.Marshal(body)
	if err != nil {
		panic(err)
	}
	return string(raw)
}

func TestCombinedStatus(t *testing.T) {
	const (
		push     = "ci/woodpecker/push/woodpecker"
		pushDocs = "ci/woodpecker/push/docs"
		cron     = "ci/woodpecker/cron/woodpecker"
		manual   = "ci/woodpecker/manual/woodpecker"
		pr       = "ci/woodpecker/pr/woodpecker"
	)
	tests := []struct {
		name string
		body string
		want CIState
	}{
		{"success", combined([2]string{push, "success"}), StateSuccess},
		{"pending", combined([2]string{push, "pending"}), StatePending},
		{"failure", combined([2]string{push, "failure"}), StateFailure},
		{"error is a failure", combined([2]string{push, "error"}), StateFailure},
		{"no statuses yet is pending", combined(), StatePending},
		{"unknown state is pending", combined([2]string{push, "weird"}), StatePending},
		{"cron failure does not reject a passing push", combined([2]string{push, "success"}, [2]string{cron, "failure"}), StateSuccess},
		{"cron success alone does not approve", combined([2]string{cron, "success"}), StatePending},
		{"manual and pr success do not approve", combined([2]string{manual, "success"}, [2]string{pr, "success"}), StatePending},
		{"cron success does not approve a pending push", combined([2]string{push, "pending"}, [2]string{cron, "success"}), StatePending},
		{"push failure rejects despite cron success", combined([2]string{push, "failure"}, [2]string{cron, "success"}), StateFailure},
		{"every push workflow must pass", combined([2]string{push, "success"}, [2]string{pushDocs, "failure"}), StateFailure},
		{"a pending push workflow holds the gate", combined([2]string{push, "success"}, [2]string{pushDocs, "pending"}), StatePending},
		{"all push workflows passing approves", combined([2]string{push, "success"}, [2]string{pushDocs, "success"}), StateSuccess},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/repos/whexy/dotfiles/commits/abc123/status" {
					t.Errorf("unexpected path %q", r.URL.Path)
				}
				if got := r.URL.Query().Get("per_page"); got != "100" {
					t.Errorf("per_page = %q, want the 100 maximum so no push context is paged out", got)
				}
				w.Write([]byte(tc.body))
			})

			got, err := c.CombinedStatus(context.Background(), "abc123")
			if err != nil {
				t.Fatalf("CombinedStatus: %v", err)
			}
			if got != tc.want {
				t.Errorf("state = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestCombinedStatusRateLimited(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "30")
		w.WriteHeader(http.StatusTooManyRequests)
	})

	_, err := c.CombinedStatus(context.Background(), "abc123")
	var rl *RateLimitError
	if !errors.As(err, &rl) {
		t.Fatalf("expected RateLimitError, got %v", err)
	}
	if rl.RetryAfter != 30*time.Second {
		t.Errorf("RetryAfter = %v", rl.RetryAfter)
	}
}
