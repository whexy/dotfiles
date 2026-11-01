package report

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"dotfiles-upgraded/internal/state"
)

func TestReportSendsTokenAndPayload(t *testing.T) {
	var auth string
	var body payload
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
	}))
	defer server.Close()

	tokenFile := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenFile, []byte("s3cret\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	w := &Webhook{URL: server.URL, TokenFile: tokenFile, Host: "golf", Configuration: "golf", Mode: "darwin"}
	err := w.Report(context.Background(), state.Failure{Sha: "abc", Attempts: 3, Error: "boom", Output: []string{"line"}})
	if err != nil {
		t.Fatal(err)
	}
	if auth != "Bearer s3cret" {
		t.Fatalf("Authorization = %q", auth)
	}
	if body.Configuration != "golf" || body.Mode != "darwin" || body.Sha != "abc" || body.Attempts != 3 || body.Output[0] != "line" {
		t.Fatalf("payload = %+v", body)
	}
}

func TestReportStatusHandling(t *testing.T) {
	for status, wantPermanent := range map[int]bool{
		http.StatusBadRequest:          true,
		http.StatusUnprocessableEntity: true,
		http.StatusUnauthorized:        false,
		http.StatusNotFound:            false,
		http.StatusInternalServerError: false,
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(status)
		}))
		err := (&Webhook{URL: server.URL}).Report(context.Background(), state.Failure{})
		server.Close()
		if err == nil {
			t.Fatalf("HTTP %d: no error", status)
		}
		var rejected *RejectedError
		if errors.As(err, &rejected) != wantPermanent {
			t.Fatalf("HTTP %d: permanent = %v, want %v", status, !wantPermanent, wantPermanent)
		}
	}
}

func TestMissingTokenIsRetried(t *testing.T) {
	w := &Webhook{URL: "http://127.0.0.1:1", TokenFile: filepath.Join(t.TempDir(), "absent")}
	err := w.Report(context.Background(), state.Failure{})
	var rejected *RejectedError
	if err == nil || errors.As(err, &rejected) {
		t.Fatalf("err = %v, want a retryable error", err)
	}
}
