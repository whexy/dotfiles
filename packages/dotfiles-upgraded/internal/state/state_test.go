package state

import (
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store, err := NewStore(t.TempDir(), log)
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	return store
}

func TestSaveLoadRoundTrip(t *testing.T) {
	store := testStore(t)
	at := time.Date(2026, 9, 17, 4, 12, 3, 0, time.UTC)
	want := State{
		ETag:           `W/"abc"`,
		LastSeenSha:    "deadbeef",
		LastSuccessSha: "cafebabe",
		LastSuccessAt:  &at,
		IgnoredShas:    []string{"1111", "2222"},
	}

	if err := store.Save(want); err != nil {
		t.Fatalf("Save: %v", err)
	}
	got := store.Load()

	if got.ETag != want.ETag || got.LastSeenSha != want.LastSeenSha || got.LastSuccessSha != want.LastSuccessSha {
		t.Fatalf("round trip mismatch: got %+v want %+v", got, want)
	}
	if got.LastSuccessAt == nil || !got.LastSuccessAt.Equal(at) {
		t.Fatalf("LastSuccessAt = %v, want %v", got.LastSuccessAt, at)
	}
	if len(got.IgnoredShas) != 2 || got.IgnoredShas[0] != "1111" {
		t.Fatalf("IgnoredShas = %v", got.IgnoredShas)
	}
}

func TestLoadMissingFileStartsFresh(t *testing.T) {
	store := testStore(t)
	got := store.Load()
	if got.LastSuccessSha != "" || got.ETag != "" || got.LastSeenSha != "" || got.LastSuccessAt != nil || len(got.IgnoredShas) != 0 {
		t.Fatalf("expected zero state, got %+v", got)
	}
}

func TestLoadCorruptFileStartsFresh(t *testing.T) {
	store := testStore(t)
	path := filepath.Join(store.dir, stateFile)
	if err := os.WriteFile(path, []byte("{not json"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	got := store.Load()
	if got.LastSuccessSha != "" || got.ETag != "" {
		t.Fatalf("expected fresh state after corruption, got %+v", got)
	}

	// A fresh state must still be persistable over the corrupt file.
	if err := store.Save(State{LastSuccessSha: "new"}); err != nil {
		t.Fatalf("Save after corruption: %v", err)
	}
	if store.Load().LastSuccessSha != "new" {
		t.Fatal("state not recovered after corruption")
	}
}

func TestWriteStatusFieldNames(t *testing.T) {
	store := testStore(t)
	at := time.Date(2026, 9, 17, 4, 12, 3, 0, time.UTC)
	if err := store.WriteStatus(Status{
		LastCheck:      at,
		LastSuccessSha: "abc",
		LastSuccessAt:  &at,
	}); err != nil {
		t.Fatalf("WriteStatus: %v", err)
	}

	raw, err := os.ReadFile(store.StatusPath())
	if err != nil {
		t.Fatalf("read status: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("status is not valid json: %v", err)
	}

	for _, key := range []string{"lastCheck", "lastSuccessSha", "lastSuccessAt", "lastError", "consecutiveFailures", "ignoredShas"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("status file missing field %q", key)
		}
	}
	if decoded["lastError"] != nil {
		t.Errorf("lastError = %v, want null", decoded["lastError"])
	}
	if got, ok := decoded["ignoredShas"].([]any); !ok || len(got) != 0 {
		t.Errorf("ignoredShas = %v, want []", decoded["ignoredShas"])
	}
}

func TestWriteLeavesNoTempFiles(t *testing.T) {
	store := testStore(t)
	if err := store.Save(State{LastSuccessSha: "a"}); err != nil {
		t.Fatalf("Save: %v", err)
	}
	if err := store.WriteStatus(Status{}); err != nil {
		t.Fatalf("WriteStatus: %v", err)
	}

	entries, err := os.ReadDir(store.dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	for _, entry := range entries {
		if entry.Name() != stateFile && entry.Name() != statusFile {
			t.Errorf("unexpected leftover file %q", entry.Name())
		}
	}
}

func TestIgnoreIsBoundedAndDeduplicated(t *testing.T) {
	var st State
	st.Ignore("a")
	st.Ignore("a")
	if len(st.IgnoredShas) != 1 {
		t.Fatalf("duplicate ignore recorded twice: %v", st.IgnoredShas)
	}

	for i := 0; i < MaxIgnored+4; i++ {
		st.Ignore(string(rune('a' + i)))
	}
	if len(st.IgnoredShas) != MaxIgnored {
		t.Fatalf("ignore set grew to %d, want %d", len(st.IgnoredShas), MaxIgnored)
	}
	if st.Ignored("a") {
		t.Error("oldest entry should have been evicted")
	}
	if !st.Ignored(string(rune('a' + MaxIgnored + 3))) {
		t.Error("newest entry should be present")
	}
}
