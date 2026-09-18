// Package github reads the tracked ref and its CI verdict from the GitHub
// REST API. It only ever makes outbound requests and never needs a credential;
// a token, when present, buys free 304s and a per-token rate limit.
package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

const (
	apiVersion = "2022-11-28"
	userAgent  = "dotfiles-upgraded"
	// maxBody caps what is read from an unexpected response body so a
	// misrouted request cannot exhaust memory.
	maxBody = 1 << 20
)

// CIState is the combined commit status. Check runs are deliberately not
// consulted: Woodpecker reports through the commit status API, so the combined
// state is the whole verdict.
type CIState string

const (
	StateSuccess CIState = "success"
	StatePending CIState = "pending"
	StateFailure CIState = "failure"
)

// RateLimitError reports a 403/429 and how long the API asked us to wait.
// RetryAfter is zero when the response carried no usable hint.
type RateLimitError struct {
	StatusCode int
	RetryAfter time.Duration
}

func (e *RateLimitError) Error() string {
	return fmt.Sprintf("github rate limited (HTTP %d, retry after %s)", e.StatusCode, e.RetryAfter)
}

// Client talks to one repository.
type Client struct {
	HTTP    *http.Client
	BaseURL string
	Repo    string
	Token   string
	// Now is injected so tests can compute rate-limit waits without real time.
	Now func() time.Time
}

// New builds a client for owner/name against the public API.
func New(repo, token string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return &Client{
		HTTP:    httpClient,
		BaseURL: "https://api.github.com",
		Repo:    repo,
		Token:   token,
		Now:     time.Now,
	}
}

// RefResult carries the outcome of a conditional ref lookup.
type RefResult struct {
	// NotModified is set for a 304; SHA and ETag are then unchanged.
	NotModified bool
	SHA         string
	ETag        string
	// PollInterval mirrors the x-poll-interval header, which GitHub raises
	// under load and expects clients to obey.
	PollInterval time.Duration
}

// Head resolves the tip commit of ref, sending etag as If-None-Match.
func (c *Client) Head(ctx context.Context, ref, etag string) (RefResult, error) {
	url := fmt.Sprintf("%s/repos/%s/commits/%s", c.BaseURL, c.Repo, ref)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return RefResult{}, err
	}
	c.setHeaders(req)
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return RefResult{}, err
	}
	defer drainAndClose(resp)

	result := RefResult{PollInterval: pollInterval(resp)}

	switch resp.StatusCode {
	case http.StatusNotModified:
		result.NotModified = true
		result.ETag = etag
		return result, nil
	case http.StatusOK:
	case http.StatusForbidden, http.StatusTooManyRequests:
		return result, c.rateLimitError(resp)
	default:
		return result, unexpected(resp)
	}

	var body struct {
		SHA string `json:"sha"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBody)).Decode(&body); err != nil {
		return result, fmt.Errorf("decode commit: %w", err)
	}
	if body.SHA == "" {
		return result, errors.New("commit response has no sha")
	}
	result.SHA = body.SHA
	result.ETag = resp.Header.Get("ETag")
	return result, nil
}

// CombinedStatus returns the combined CI state for sha. An unknown or absent
// state is reported as pending: no reported status yet is indistinguishable
// from CI not having started, and treating it as failure would strand commits.
func (c *Client) CombinedStatus(ctx context.Context, sha string) (CIState, error) {
	url := fmt.Sprintf("%s/repos/%s/commits/%s/status", c.BaseURL, c.Repo, sha)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	c.setHeaders(req)

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer drainAndClose(resp)

	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusForbidden, http.StatusTooManyRequests:
		return "", c.rateLimitError(resp)
	default:
		return "", unexpected(resp)
	}

	var body struct {
		State    string `json:"state"`
		Statuses []struct {
			State string `json:"state"`
		} `json:"statuses"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBody)).Decode(&body); err != nil {
		return "", fmt.Errorf("decode status: %w", err)
	}

	switch body.State {
	case "success":
		// GitHub reports "success" for a commit with no statuses at all, so
		// an empty list means CI has not reported yet, not that it passed.
		if len(body.Statuses) == 0 {
			return StatePending, nil
		}
		return StateSuccess, nil
	case "failure", "error":
		return StateFailure, nil
	default:
		return StatePending, nil
	}
}

func (c *Client) setHeaders(req *http.Request) {
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", apiVersion)
	req.Header.Set("User-Agent", userAgent)
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
}

func (c *Client) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// rateLimitError extracts the wait hint GitHub supplies, preferring the
// explicit Retry-After over the reset timestamp.
func (c *Client) rateLimitError(resp *http.Response) error {
	err := &RateLimitError{StatusCode: resp.StatusCode}

	if v := resp.Header.Get("Retry-After"); v != "" {
		if secs, parseErr := strconv.Atoi(v); parseErr == nil && secs > 0 {
			err.RetryAfter = time.Duration(secs) * time.Second
			return err
		}
	}
	if v := resp.Header.Get("X-RateLimit-Reset"); v != "" {
		if unix, parseErr := strconv.ParseInt(v, 10, 64); parseErr == nil {
			if wait := time.Unix(unix, 0).Sub(c.now()); wait > 0 {
				err.RetryAfter = wait
			}
			return err
		}
	}
	return err
}

func pollInterval(resp *http.Response) time.Duration {
	v := resp.Header.Get("X-Poll-Interval")
	if v == "" {
		return 0
	}
	secs, err := strconv.Atoi(v)
	if err != nil || secs <= 0 {
		return 0
	}
	return time.Duration(secs) * time.Second
}

func unexpected(resp *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return fmt.Errorf("github %s: unexpected status %d: %s", resp.Request.URL.Path, resp.StatusCode, string(body))
}

func drainAndClose(resp *http.Response) {
	io.Copy(io.Discard, io.LimitReader(resp.Body, maxBody))
	resp.Body.Close()
}
