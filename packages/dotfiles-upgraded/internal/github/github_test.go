package github

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"
)

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
		w.Write([]byte(`{"sha":"abc123"}`))
	})

	if _, err := c.Head(context.Background(), "master", ""); err != nil {
		t.Fatalf("Head: %v", err)
	}
	if got.Get("Accept") != "application/vnd.github+json" {
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
		w.Write([]byte(`{"sha":"abc123"}`))
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
		w.Write([]byte(`{"sha":"abc123"}`))
	})

	first, err := c.Head(context.Background(), "master", "")
	if err != nil {
		t.Fatalf("first Head: %v", err)
	}
	if first.NotModified {
		t.Fatal("first request should not be a 304")
	}
	if first.SHA != "abc123" {
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

func TestHeadHonoursPollInterval(t *testing.T) {
	c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Poll-Interval", "120")
		w.Write([]byte(`{"sha":"abc123"}`))
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

func TestCombinedStatus(t *testing.T) {
	tests := []struct {
		name string
		body string
		want CIState
	}{
		{"success", `{"state":"success","statuses":[{"state":"success"}]}`, StateSuccess},
		{"pending", `{"state":"pending","statuses":[{"state":"pending"}]}`, StatePending},
		{"failure", `{"state":"failure","statuses":[{"state":"failure"}]}`, StateFailure},
		{"error is a failure", `{"state":"error","statuses":[{"state":"error"}]}`, StateFailure},
		{"no statuses yet is pending", `{"state":"success","statuses":[]}`, StatePending},
		{"unknown state is pending", `{"state":"weird","statuses":[{"state":"weird"}]}`, StatePending},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/repos/whexy/dotfiles/commits/abc123/status" {
					t.Errorf("unexpected path %q", r.URL.Path)
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
