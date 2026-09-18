// Package engine implements the poll → gate → switch → record loop.
//
// Every effect the loop depends on (time, GitHub, the rebuild itself) arrives
// through an interface, so the whole state machine is exercised in tests
// without a clock, a network or a Nix store.
package engine

import (
	"context"
	"errors"
	"fmt"
	"hash/fnv"
	"log/slog"
	"time"

	"dotfiles-upgraded/internal/github"
	"dotfiles-upgraded/internal/state"
)

// Clock abstracts the passage of time.
type Clock interface {
	Now() time.Time
	// Sleep returns false when ctx ended before d elapsed.
	Sleep(ctx context.Context, d time.Duration) bool
}

// Refs resolves the tracked ref and its CI verdict.
type Refs interface {
	Head(ctx context.Context, ref, etag string) (github.RefResult, error)
	CombinedStatus(ctx context.Context, sha string) (github.CIState, error)
}

// Switcher applies a commit to this host.
type Switcher interface {
	Switch(ctx context.Context, sha string) error
}

// Config holds the tuning the module surface exposes.
type Config struct {
	Ref            string
	PollInterval   time.Duration
	MaxAttempts    int
	RequireCIPass  bool
	PendingTimeout time.Duration
	// JitterSeed keeps each host's tick offset stable and distinct, so the
	// fleet does not converge on a synchronised poll.
	JitterSeed string
}

const (
	// jitterFraction spreads ticks over ±20% of the interval.
	jitterFraction = 0.2
	// backoffBase and backoffMax bound the retry schedule between switch
	// attempts: long enough for a transient outage to heal, short enough that
	// a fixed cache recovers within one poll cycle.
	backoffBase = 1 * time.Minute
	backoffMax  = 30 * time.Minute
	// rateLimitFallback applies when a 403/429 carries no usable wait hint.
	rateLimitFallback = 15 * time.Minute
)

// Store is the subset of state persistence the engine needs.
type Store interface {
	Load() state.State
	Save(state.State) error
	WriteStatus(state.Status) error
}

// Engine runs the loop.
type Engine struct {
	Config   Config
	Refs     Refs
	Switcher Switcher
	Store    Store
	Clock    Clock
	Log      *slog.Logger

	st state.State
	// pendingSince tracks how long the current candidate has sat in CI, so a
	// never-resolving status is eventually abandoned instead of polled forever.
	pendingSince    map[string]time.Time
	consecutiveFail int
	lastError       *string
	// serverInterval holds an x-poll-interval floor requested by GitHub.
	serverInterval time.Duration
}

// New prepares an engine with state loaded from the store.
func New(cfg Config, refs Refs, sw Switcher, store Store, clock Clock, log *slog.Logger) *Engine {
	e := &Engine{
		Config:       cfg,
		Refs:         refs,
		Switcher:     sw,
		Store:        store,
		Clock:        clock,
		Log:          log,
		pendingSince: map[string]time.Time{},
	}
	e.st = store.Load()
	return e
}

// Run polls until ctx ends.
func (e *Engine) Run(ctx context.Context) {
	for {
		wait := e.RunOnce(ctx)
		if ctx.Err() != nil {
			return
		}
		if !e.Clock.Sleep(ctx, wait) {
			return
		}
	}
}

// RunOnce performs one cycle and returns how long to wait before the next.
func (e *Engine) RunOnce(ctx context.Context) time.Duration {
	wait := e.cycle(ctx)
	e.writeStatus()
	return wait
}

// cycle is one pass of the state machine; the returned duration is the delay
// before the next poll.
func (e *Engine) cycle(ctx context.Context) time.Duration {
	head, err := e.Refs.Head(ctx, e.Config.Ref, e.st.ETag)
	if err != nil {
		var rl *github.RateLimitError
		if errors.As(err, &rl) {
			e.recordFailure(fmt.Sprintf("rate limited: %v", err))
			wait := rl.RetryAfter
			if wait <= 0 {
				wait = rateLimitFallback
			}
			e.Log.Warn("backing off after rate limit", "status", rl.StatusCode, "wait", wait.String())
			return wait
		}
		e.recordFailure(fmt.Sprintf("ref lookup failed: %v", err))
		e.Log.Warn("ref lookup failed", "error", err)
		return e.nextInterval()
	}

	if head.PollInterval > 0 {
		e.serverInterval = head.PollInterval
	}

	// A 304 only says the tip is still LastSeenSha; that commit may still be
	// waiting on CI or a retried switch, so the cycle continues with it.
	sha := e.st.LastSeenSha
	if head.NotModified {
		e.Log.Debug("ref unchanged", "sha", sha)
		if sha == "" {
			e.recordSuccessfulCheck()
			return e.nextInterval()
		}
	} else {
		sha = head.SHA
		if sha != e.st.LastSeenSha || head.ETag != e.st.ETag {
			if sha != e.st.LastSeenSha {
				e.Log.Info("ref head", "sha", sha)
				// Only the tip is ever a candidate, so a superseded commit's
				// pending clock has nothing left to measure.
				clear(e.pendingSince)
			}
			e.st.LastSeenSha = sha
			e.st.ETag = head.ETag
			e.persist()
		}
	}

	if sha == e.st.LastSuccessSha {
		e.recordSuccessfulCheck()
		return e.nextInterval()
	}
	if e.st.Ignored(sha) {
		e.Log.Debug("sha ignored", "sha", sha)
		e.recordSuccessfulCheck()
		return e.nextInterval()
	}

	if e.Config.RequireCIPass {
		ciState, err := e.Refs.CombinedStatus(ctx, sha)
		if err != nil {
			var rl *github.RateLimitError
			if errors.As(err, &rl) {
				e.recordFailure(fmt.Sprintf("rate limited: %v", err))
				wait := rl.RetryAfter
				if wait <= 0 {
					wait = rateLimitFallback
				}
				return wait
			}
			e.recordFailure(fmt.Sprintf("ci status failed: %v", err))
			e.Log.Warn("ci status lookup failed", "sha", sha, "error", err)
			return e.nextInterval()
		}

		switch ciState {
		case github.StateSuccess:
			delete(e.pendingSince, sha)
		case github.StateFailure:
			e.Log.Info("ci failed, ignoring sha", "sha", sha)
			e.ignore(sha)
			e.recordSuccessfulCheck()
			return e.nextInterval()
		default:
			if e.pendingTooLong(sha) {
				e.Log.Warn("ci stayed pending, ignoring sha", "sha", sha)
				e.ignore(sha)
			} else {
				e.Log.Info("ci pending", "sha", sha)
			}
			e.recordSuccessfulCheck()
			return e.nextInterval()
		}
	}

	e.attemptSwitch(ctx, sha)
	return e.nextInterval()
}

// attemptSwitch retries a failing switch with bounded backoff, then gives up on
// the SHA. A transient fault and a genuinely broken commit are indistinguishable
// by exit code, so retrying first lets transients heal while the ignore keeps a
// bad commit from blocking the next one.
func (e *Engine) attemptSwitch(ctx context.Context, sha string) {
	attempts := e.Config.MaxAttempts
	if attempts < 1 {
		attempts = 1
	}

	for attempt := 1; attempt <= attempts; attempt++ {
		err := e.Switcher.Switch(ctx, sha)
		if err == nil {
			now := e.Clock.Now()
			e.st.LastSuccessSha = sha
			e.st.LastSuccessAt = &now
			e.st.IgnoredShas = nil
			e.persist()
			e.consecutiveFail = 0
			e.lastError = nil
			e.Log.Info("switched", "sha", sha)
			return
		}
		if ctx.Err() != nil {
			e.recordFailure(fmt.Sprintf("switch interrupted: %v", err))
			return
		}

		e.recordFailure(fmt.Sprintf("switch attempt %d/%d failed: %v", attempt, attempts, err))
		e.Log.Warn("switch failed", "sha", sha, "attempt", attempt, "attempts", attempts, "error", err)
		e.writeStatus()

		if attempt == attempts {
			break
		}
		if !e.Clock.Sleep(ctx, Backoff(attempt)) {
			return
		}
	}

	e.Log.Warn("giving up on sha", "sha", sha, "attempts", attempts)
	e.ignore(sha)
}

// Backoff returns the delay after a given attempt number (1-based), doubling
// from backoffBase and clamped at backoffMax.
func Backoff(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	d := backoffBase
	for i := 1; i < attempt; i++ {
		d *= 2
		if d >= backoffMax {
			return backoffMax
		}
	}
	return d
}

func (e *Engine) pendingTooLong(sha string) bool {
	now := e.Clock.Now()
	first, seen := e.pendingSince[sha]
	if !seen {
		e.pendingSince[sha] = now
		return false
	}
	return e.Config.PendingTimeout > 0 && now.Sub(first) >= e.Config.PendingTimeout
}

func (e *Engine) ignore(sha string) {
	e.st.Ignore(sha)
	delete(e.pendingSince, sha)
	e.persist()
}

func (e *Engine) persist() {
	if err := e.Store.Save(e.st); err != nil {
		e.Log.Warn("could not save state", "error", err)
	}
}

func (e *Engine) recordSuccessfulCheck() {
	e.consecutiveFail = 0
	e.lastError = nil
}

func (e *Engine) recordFailure(msg string) {
	e.consecutiveFail++
	e.lastError = &msg
}

func (e *Engine) writeStatus() {
	st := state.Status{
		LastCheck:           e.Clock.Now(),
		LastSuccessSha:      e.st.LastSuccessSha,
		LastSuccessAt:       e.st.LastSuccessAt,
		LastError:           e.lastError,
		ConsecutiveFailures: e.consecutiveFail,
		IgnoredShas:         e.st.IgnoredShas,
	}
	if err := e.Store.WriteStatus(st); err != nil {
		e.Log.Warn("could not write status", "error", err)
	}
}

// nextInterval applies per-host jitter and respects a server-requested floor.
func (e *Engine) nextInterval() time.Duration {
	base := e.Config.PollInterval
	if e.serverInterval > base {
		base = e.serverInterval
	}
	wait := jitter(base, e.Config.JitterSeed, e.Clock.Now())
	// x-poll-interval is a minimum GitHub asks clients to honour, so jitter
	// may only lengthen the wait once the server has set one.
	if wait < e.serverInterval {
		wait = e.serverInterval
	}
	return wait
}

// jitter offsets the interval by up to ±jitterFraction. The offset is derived
// from the host seed and the current tick so hosts stay spread out without
// needing a random source.
func jitter(base time.Duration, seed string, now time.Time) time.Duration {
	if base <= 0 {
		return base
	}
	h := fnv.New64a()
	h.Write([]byte(seed))
	var tick [8]byte
	n := now.UnixNano()
	for i := range tick {
		tick[i] = byte(n >> (8 * i))
	}
	h.Write(tick[:])

	span := float64(base) * jitterFraction
	// Map the hash onto [-span, +span].
	frac := float64(h.Sum64()%2001)/1000.0 - 1.0
	return time.Duration(float64(base) + frac*span)
}
