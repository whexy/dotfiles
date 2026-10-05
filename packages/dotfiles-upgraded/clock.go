package main

import (
	"context"
	"time"
)

// wakeCheckInterval bounds how late a wait can end after the host resumes
// from sleep.
const wakeCheckInterval = time.Minute

// realClock measures waits against the wall clock. Go timers run on the
// monotonic clock, which stops while macOS sleeps, so a plain timer started
// before a suspend would overshoot its deadline by the whole time asleep. A
// laptop that mostly sleeps would then poll only when it happened to stay
// awake for a full interval.
type realClock struct {
	// tick and wall are overridden only by tests.
	tick time.Duration
	wall func() time.Time
}

func (realClock) Now() time.Time { return time.Now() }

func (c realClock) wallNow() time.Time {
	if c.wall != nil {
		return c.wall()
	}
	// Round(0) strips the monotonic reading so comparisons use wall time.
	return time.Now().Round(0)
}

func (c realClock) Sleep(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	tick := c.tick
	if tick <= 0 {
		tick = wakeCheckInterval
	}
	deadline := c.wallNow().Add(d)
	for {
		remaining := deadline.Sub(c.wallNow())
		if remaining <= 0 {
			return true
		}
		timer := time.NewTimer(min(remaining, tick))
		select {
		case <-ctx.Done():
			timer.Stop()
			return false
		case <-timer.C:
		}
	}
}
