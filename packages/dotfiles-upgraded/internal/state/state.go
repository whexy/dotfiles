// Package state persists what the daemon must remember across restarts and
// publishes the health file an operator (or later, monitoring) reads.
package state

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"time"
)

// MaxIgnored bounds the ignore ring buffer. A skipped commit is superseded by
// the next one, so old entries have no value once the buffer wraps.
const MaxIgnored = 8

const (
	stateFile  = "state.json"
	statusFile = "status.json"
	lockFile   = "lock"
)

// State is the daemon's private memory. LastSuccessSha is the last
// successfully *applied* commit, never the last seen one, so an interrupted or
// failed switch never looks converged.
type State struct {
	ETag           string     `json:"etag"`
	LastSeenSha    string     `json:"lastSeenSha"`
	LastSuccessSha string     `json:"lastSuccessSha"`
	LastSuccessAt  *time.Time `json:"lastSuccessAt"`
	IgnoredShas    []string   `json:"ignoredShas"`
}

// Ignored reports whether sha was given up on.
func (s *State) Ignored(sha string) bool {
	for _, ignored := range s.IgnoredShas {
		if ignored == sha {
			return true
		}
	}
	return false
}

// Ignore appends sha, dropping the oldest entry beyond MaxIgnored.
func (s *State) Ignore(sha string) {
	if s.Ignored(sha) {
		return
	}
	s.IgnoredShas = append(s.IgnoredShas, sha)
	if len(s.IgnoredShas) > MaxIgnored {
		s.IgnoredShas = s.IgnoredShas[len(s.IgnoredShas)-MaxIgnored:]
	}
}

// Status is the health file described by the design: the only externally
// visible signal that an unattended host is still converging.
type Status struct {
	LastCheck           time.Time  `json:"lastCheck"`
	LastSuccessSha      string     `json:"lastSuccessSha"`
	LastSuccessAt       *time.Time `json:"lastSuccessAt"`
	LastError           *string    `json:"lastError"`
	ConsecutiveFailures int        `json:"consecutiveFailures"`
	IgnoredShas         []string   `json:"ignoredShas"`
}

// Store reads and writes the files under a single state directory.
type Store struct {
	dir string
	log *slog.Logger
}

// NewStore creates the state directory if needed.
func NewStore(dir string, log *slog.Logger) (*Store, error) {
	if dir == "" {
		return nil, errors.New("state directory is empty")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create state directory: %w", err)
	}
	return &Store{dir: dir, log: log}, nil
}

// LockPath is the file the switcher flocks to exclude concurrent rebuilds.
func (s *Store) LockPath() string { return filepath.Join(s.dir, lockFile) }

// Load returns the persisted state. A missing or unreadable file yields a
// fresh state: refusing to start because of a damaged cache would strand the
// host on its current generation forever, which is worse than one extra
// rebuild.
func (s *Store) Load() State {
	path := filepath.Join(s.dir, stateFile)
	raw, err := os.ReadFile(path)
	if err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			s.log.Warn("state file unreadable, starting fresh", "path", path, "error", err)
		}
		return State{}
	}
	var st State
	if err := json.Unmarshal(raw, &st); err != nil {
		s.log.Warn("state file corrupt, starting fresh", "path", path, "error", err)
		return State{}
	}
	return st
}

// Save persists the state atomically.
func (s *Store) Save(st State) error {
	if st.IgnoredShas == nil {
		st.IgnoredShas = []string{}
	}
	return s.writeJSON(stateFile, st)
}

// WriteStatus publishes the health file atomically.
func (s *Store) WriteStatus(st Status) error {
	if st.IgnoredShas == nil {
		st.IgnoredShas = []string{}
	}
	return s.writeJSON(statusFile, st)
}

// StatusPath is where the health file is published.
func (s *Store) StatusPath() string { return filepath.Join(s.dir, statusFile) }

// writeJSON writes via a temporary file and rename so a crash mid-write never
// leaves a truncated file behind.
func (s *Store) writeJSON(name string, value any) error {
	raw, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", name, err)
	}
	raw = append(raw, '\n')

	tmp, err := os.CreateTemp(s.dir, name+".*")
	if err != nil {
		return fmt.Errorf("create temp for %s: %w", name, err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if _, err := tmp.Write(raw); err != nil {
		tmp.Close()
		return fmt.Errorf("write %s: %w", name, err)
	}
	if err := tmp.Chmod(0o644); err != nil {
		tmp.Close()
		return fmt.Errorf("chmod %s: %w", name, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close %s: %w", name, err)
	}
	if err := os.Rename(tmpName, filepath.Join(s.dir, name)); err != nil {
		return fmt.Errorf("rename %s: %w", name, err)
	}
	return nil
}
