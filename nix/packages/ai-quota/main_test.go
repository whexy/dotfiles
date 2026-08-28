package main

import "testing"

func TestHumanDeltaUsesElapsedUnits(t *testing.T) {
	tests := []struct {
		seconds int64
		want    string
	}{
		{0, "now"},
		{59, "0m"},
		{60, "1m"},
		{3599, "59m"},
		{3600, "1h 0m"},
		{13207, "3h 40m"},
		{86399, "23h 59m"},
		{86400, "1d 0h"},
		{176400, "2d 1h"},
	}

	for _, tt := range tests {
		if got := humanDelta(tt.seconds); got != tt.want {
			t.Errorf("humanDelta(%d) = %q, want %q", tt.seconds, got, tt.want)
		}
	}
}
