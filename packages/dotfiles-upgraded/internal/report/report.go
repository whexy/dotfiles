// Package report delivers a given-up switch to the failure webhook, which
// files it as a GitHub issue. The webhook holds the GitHub credential, so a
// host needs only the webhook's bearer token.
package report

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"dotfiles-upgraded/internal/state"
)

// Webhook posts failures for one host.
type Webhook struct {
	HTTP *http.Client
	URL  string
	// TokenFile is read on every delivery, so a token that agenix decrypts
	// after the daemon starts, or a rotated one, is picked up without a
	// restart.
	TokenFile     string
	Host          string
	Configuration string
	Mode          string
}

// payload is the webhook's request body. The workflow that receives it
// (n8n/failure-report.json) reads these field names.
type payload struct {
	Host          string    `json:"host"`
	Configuration string    `json:"configuration"`
	Mode          string    `json:"mode"`
	Sha           string    `json:"sha"`
	Attempts      int       `json:"attempts"`
	Error         string    `json:"error"`
	FailedAt      time.Time `json:"failedAt"`
	Output        []string  `json:"output"`
}

// RejectedError is a report the webhook refused as malformed. Sending it again
// cannot succeed.
type RejectedError struct {
	StatusCode int
	Body       string
}

func (e *RejectedError) Error() string {
	return fmt.Sprintf("failure webhook rejected the report (HTTP %d): %s", e.StatusCode, e.Body)
}

// Permanent marks the error as not worth retrying.
func (*RejectedError) Permanent() bool { return true }

// Report delivers f. Any error other than RejectedError leaves the report to be
// sent again: a missing token, an unregistered webhook (404) and a failing
// GitHub call (5xx) all heal without the host changing.
func (w *Webhook) Report(ctx context.Context, f state.Failure) error {
	body, err := json.Marshal(payload{
		Host:          w.Host,
		Configuration: w.Configuration,
		Mode:          w.Mode,
		Sha:           f.Sha,
		Attempts:      f.Attempts,
		Error:         f.Error,
		FailedAt:      f.FailedAt,
		Output:        f.Output,
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.URL, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "dotfiles-upgraded")
	if w.TokenFile != "" {
		token, err := os.ReadFile(w.TokenFile)
		if err != nil {
			return fmt.Errorf("read webhook token: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	}

	client := w.HTTP
	if client == nil {
		client = &http.Client{Timeout: time.Minute}
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	text, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))

	switch {
	case resp.StatusCode >= 200 && resp.StatusCode < 300:
		return nil
	case resp.StatusCode == http.StatusBadRequest,
		resp.StatusCode == http.StatusRequestEntityTooLarge,
		resp.StatusCode == http.StatusUnprocessableEntity:
		return &RejectedError{StatusCode: resp.StatusCode, Body: string(text)}
	default:
		return fmt.Errorf("failure webhook: HTTP %d: %s", resp.StatusCode, text)
	}
}
