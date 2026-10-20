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
type realClock struct{}

func (realClock) Now() time.Time { return time.Now() }

// wallNow strips the monotonic reading so comparisons use wall time.
func wallNow() time.Time { return time.Now().Round(0) }

func (realClock) Sleep(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	deadline := wallNow().Add(d)
	for {
		remaining := deadline.Sub(wallNow())
		if remaining <= 0 {
			return true
		}
		timer := time.NewTimer(min(remaining, wakeCheckInterval))
		select {
		case <-ctx.Done():
			timer.Stop()
			return false
		case <-timer.C:
		}
	}
}
