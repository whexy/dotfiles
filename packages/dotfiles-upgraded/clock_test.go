package main

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

// A suspend freezes timers but not the wall clock; jumping the wall clock past
// the deadline must end the wait at the next tick.
func TestSleepEndsAfterWallClockJump(t *testing.T) {
	start := time.Date(2026, 10, 5, 5, 0, 0, 0, time.UTC)
	var offset atomic.Int64
	c := realClock{
		tick: 5 * time.Millisecond,
		wall: func() time.Time { return start.Add(time.Duration(offset.Load())) },
	}

	done := make(chan bool, 1)
	go func() { done <- c.Sleep(context.Background(), 10*time.Minute) }()

	select {
	case <-done:
		t.Fatal("sleep ended before its deadline")
	case <-time.After(50 * time.Millisecond):
	}

	offset.Store(int64(6 * time.Hour))
	select {
	case ok := <-done:
		if !ok {
			t.Fatal("sleep reported cancellation")
		}
	case <-time.After(time.Second):
		t.Fatal("sleep ignored the wall-clock jump")
	}
}

func TestSleepWaitsForShortDeadline(t *testing.T) {
	c := realClock{tick: time.Hour}
	begin := time.Now()
	if !c.Sleep(context.Background(), 20*time.Millisecond) {
		t.Fatal("sleep reported cancellation")
	}
	if elapsed := time.Since(begin); elapsed < 20*time.Millisecond || elapsed > time.Second {
		t.Fatalf("sleep took %v", elapsed)
	}
}

func TestSleepStopsOnCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan bool, 1)
	go func() { done <- realClock{}.Sleep(ctx, time.Hour) }()
	cancel()
	select {
	case ok := <-done:
		if ok {
			t.Fatal("cancelled sleep reported completion")
		}
	case <-time.After(time.Second):
		t.Fatal("sleep ignored cancellation")
	}
}
