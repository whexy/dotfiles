package announce

import (
	"bufio"
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	// idleTimeout drops a stream that has sent nothing, not even ntfy's
	// keepalive (every 45s by default), so a connection that died silently,
	// as one does across a laptop's sleep, is replaced.
	idleTimeout = 3 * time.Minute
	minBackoff  = 5 * time.Second
	maxBackoff  = time.Minute
	// maxLine bounds one ntfy event; an announcement is a few hundred bytes.
	maxLine = 64 << 10
)

// Publish posts message to an ntfy topic URL with a bearer token.
func Publish(ctx context.Context, client *http.Client, topicURL, token, message string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, topicURL, strings.NewReader(message))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "text/plain")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("ntfy answered %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

// Status is the subscription's health as status.json reports it.
type Status struct {
	Connected   bool
	LastEventAt *time.Time
}

// Subscriber holds a stream to an ntfy topic and keeps the newest verified
// announcement for the engine to take.
type Subscriber struct {
	TopicURL  string
	PublicKey ed25519.PublicKey
	Repo      string
	Ref       string
	// Grace is how long the stream may stay down before Healthy turns false,
	// so a relay restart does not send the whole fleet to GitHub.
	Grace time.Duration
	HTTP  *http.Client
	Log   *slog.Logger

	mu        sync.Mutex
	latest    *Announcement
	delivered int64
	connected bool
	healthy   bool
	downSince time.Time
	lastEvent *time.Time
	wake      chan struct{}
}

// NewSubscriber prepares a subscriber; Run starts it.
func NewSubscriber(topicURL string, pub ed25519.PublicKey, repo, ref string, log *slog.Logger) *Subscriber {
	return &Subscriber{
		TopicURL:  strings.TrimRight(topicURL, "/"),
		PublicKey: pub,
		Repo:      repo,
		Ref:       ref,
		Grace:     5 * time.Minute,
		// No overall timeout: the response is a stream that never ends.
		HTTP: &http.Client{Transport: &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			DialContext:           (&net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
			TLSHandshakeTimeout:   30 * time.Second,
			ResponseHeaderTimeout: 30 * time.Second,
		}},
		Log:  log,
		wake: make(chan struct{}, 1),
	}
}

// Wake fires when an announcement arrives or the stream turns unhealthy.
func (s *Subscriber) Wake() <-chan struct{} { return s.wake }

// Take returns the newest announcement not yet taken.
func (s *Subscriber) Take() (Announcement, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	// The wake for this announcement is spent with it; left buffered, it
	// would end the engine's next wait early for nothing.
	select {
	case <-s.wake:
	default:
	}
	if s.latest == nil {
		return Announcement{}, false
	}
	a := *s.latest
	s.latest = nil
	return a, true
}

// Healthy reports whether the stream is up, or was down for less than Grace.
func (s *Subscriber) Healthy() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.healthy
}

// Status reports the stream's state.
func (s *Subscriber) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return Status{Connected: s.connected, LastEventAt: s.lastEvent}
}

// Run holds the subscription until ctx ends, reconnecting with backoff.
func (s *Subscriber) Run(ctx context.Context) {
	backoff := minBackoff
	for {
		opened, err := s.stream(ctx)
		s.setConnected(false)
		if ctx.Err() != nil {
			return
		}
		if opened {
			backoff = minBackoff
		}
		s.Log.Warn("announcement stream ended", "error", err, "retryIn", backoff.String())
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, maxBackoff)
		s.checkGrace()
	}
}

// stream reads one connection until it ends. opened reports whether the relay
// accepted the subscription.
func (s *Subscriber) stream(ctx context.Context) (opened bool, err error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// since=latest replays the newest cached announcement, so a host that was
	// offline or restarting catches up on connect.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.TopicURL+"/json?since=latest", nil)
	if err != nil {
		return false, err
	}
	resp, err := s.HTTP.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return false, fmt.Errorf("ntfy answered %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	s.setConnected(true)
	s.Log.Info("announcement stream connected", "url", s.TopicURL)

	watchdog := time.AfterFunc(idleTimeout, cancel)
	defer watchdog.Stop()
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 4096), maxLine)
	for scanner.Scan() {
		watchdog.Reset(idleTimeout)
		var ev struct {
			Event   string `json:"event"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &ev); err != nil {
			s.Log.Warn("unreadable ntfy event", "error", err)
			continue
		}
		s.touch()
		if ev.Event != "message" {
			continue
		}
		a, err := Verify(s.PublicKey, ev.Message)
		if err != nil {
			s.Log.Warn("rejected announcement", "error", err)
			continue
		}
		if a.Repo != s.Repo || a.Ref != s.Ref {
			s.Log.Warn("announcement for another branch", "repo", a.Repo, "ref", a.Ref)
			continue
		}
		s.offer(a)
	}
	if err := scanner.Err(); err != nil {
		return true, err
	}
	return true, errors.New("relay closed the stream")
}

func (s *Subscriber) offer(a Announcement) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if a.Seq <= s.delivered {
		return
	}
	s.delivered = a.Seq
	s.latest = &a
	s.signal()
}

func (s *Subscriber) touch() {
	now := time.Now()
	s.mu.Lock()
	s.lastEvent = &now
	s.mu.Unlock()
}

func (s *Subscriber) setConnected(up bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if up {
		s.connected, s.healthy = true, true
		return
	}
	if s.connected {
		s.downSince = time.Now()
	}
	s.connected = false
}

// checkGrace turns the subscription unhealthy once it has been down longer
// than Grace, and wakes the engine so it resumes polling GitHub at once.
func (s *Subscriber) checkGrace() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.connected || !s.healthy || time.Since(s.downSince) < s.Grace {
		return
	}
	s.healthy = false
	s.signal()
}

// signal wakes the engine without blocking; one pending wake is enough.
func (s *Subscriber) signal() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}
