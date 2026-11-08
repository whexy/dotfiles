package announce

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const sha = "1234567890123456789012345678901234567890"

func testKey(t *testing.T, fill byte) ed25519.PrivateKey {
	t.Helper()
	key, err := ParsePrivateKey(base64.StdEncoding.EncodeToString(bytesOf(fill, ed25519.SeedSize)))
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func bytesOf(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

func sign(t *testing.T, key ed25519.PrivateKey, a Announcement) string {
	t.Helper()
	msg, err := Sign(key, a)
	if err != nil {
		t.Fatal(err)
	}
	return msg
}

func TestVerify(t *testing.T) {
	key := testKey(t, 1)
	pub := key.Public().(ed25519.PublicKey)
	a := Announcement{Repo: "whexy/dotfiles", Ref: "master", Sha: sha, Seq: 7, Time: time.Unix(100, 0).UTC()}
	msg := sign(t, key, a)

	got, err := Verify(pub, msg)
	if err != nil || got != a {
		t.Fatalf("Verify = %+v, %v; want %+v", got, err, a)
	}

	if _, err := Verify(testKey(t, 2).Public().(ed25519.PublicKey), msg); err == nil {
		t.Fatal("accepted a message signed with another key")
	}

	var env envelope
	json.Unmarshal([]byte(msg), &env)
	payload, _ := base64.StdEncoding.DecodeString(env.Payload)
	env.Payload = base64.StdEncoding.EncodeToString([]byte(strings.Replace(string(payload), `"seq":7`, `"seq":9`, 1)))
	tampered, _ := json.Marshal(env)
	if _, err := Verify(pub, string(tampered)); err == nil {
		t.Fatal("accepted a tampered payload")
	}

	// A signature over the bare payload, without the context, is not valid.
	env.Payload = base64.StdEncoding.EncodeToString(payload)
	env.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(key, payload))
	bare, _ := json.Marshal(env)
	if _, err := Verify(pub, string(bare)); err == nil {
		t.Fatal("accepted a signature made without the signing context")
	}
}

func TestSignRejectsInvalid(t *testing.T) {
	key := testKey(t, 1)
	for name, a := range map[string]Announcement{
		"short sha": {Repo: "r", Ref: "master", Sha: "abc", Seq: 1},
		"zero seq":  {Repo: "r", Ref: "master", Sha: sha},
		"no ref":    {Repo: "r", Sha: sha, Seq: 1},
	} {
		if _, err := Sign(key, a); err == nil {
			t.Errorf("%s: signed", name)
		}
	}
}

func TestParseKeys(t *testing.T) {
	if _, err := ParsePrivateKey("not base64!"); err == nil {
		t.Error("accepted a non-base64 seed")
	}
	if _, err := ParsePrivateKey(base64.StdEncoding.EncodeToString(bytesOf(1, 31))); err == nil {
		t.Error("accepted a 31-byte seed")
	}
	if _, err := ParsePublicKey(base64.StdEncoding.EncodeToString(bytesOf(1, 33))); err == nil {
		t.Error("accepted a 33-byte public key")
	}
}

// relay serves an ntfy JSON stream: each connection gets the queued lines, then
// stays open until the test closes hold.
type relay struct {
	lines chan string
	hold  chan struct{}
}

func (r *relay) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.URL.Path != "/dotfiles-rollout/json" || req.URL.Query().Get("since") != "latest" {
		http.NotFound(w, req)
		return
	}
	flusher := w.(http.Flusher)
	fmt.Fprintln(w, `{"id":"o","event":"open","topic":"dotfiles-rollout"}`)
	flusher.Flush()
	for {
		select {
		case line := <-r.lines:
			fmt.Fprintln(w, line)
			flusher.Flush()
		case <-r.hold:
			return
		case <-req.Context().Done():
			return
		}
	}
}

func messageLine(msg string) string {
	raw, _ := json.Marshal(map[string]string{"id": "m", "event": "message", "topic": "dotfiles-rollout", "message": msg})
	return string(raw)
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestSubscriber(t *testing.T) {
	key := testKey(t, 1)
	r := &relay{lines: make(chan string, 16), hold: make(chan struct{})}
	server := httptest.NewServer(r)
	defer server.Close()

	sub := NewSubscriber(server.URL+"/dotfiles-rollout/", key.Public().(ed25519.PublicKey), "whexy/dotfiles", "master",
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	sub.Grace = 0
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go sub.Run(ctx)

	waitFor(t, "connection", func() bool { return sub.Healthy() && sub.Status().Connected })
	if _, ok := sub.Take(); ok {
		t.Fatal("announcement before any message")
	}

	announced := Announcement{Repo: "whexy/dotfiles", Ref: "master", Sha: sha, Seq: 5}
	r.lines <- `{"id":"k","event":"keepalive"}`
	r.lines <- messageLine(sign(t, testKey(t, 2), Announcement{Repo: "whexy/dotfiles", Ref: "master", Sha: sha, Seq: 99}))
	r.lines <- messageLine(sign(t, key, Announcement{Repo: "whexy/dotfiles", Ref: "other", Sha: sha, Seq: 98}))
	r.lines <- messageLine(sign(t, key, Announcement{Repo: "whexy/dotfiles", Ref: "master", Sha: sha, Seq: 4}))
	r.lines <- messageLine(sign(t, key, announced))
	r.lines <- messageLine(sign(t, key, Announcement{Repo: "whexy/dotfiles", Ref: "master", Sha: sha, Seq: 3}))

	select {
	case <-sub.Wake():
	case <-time.After(5 * time.Second):
		t.Fatal("no wake for an announcement")
	}
	waitFor(t, "every line", func() bool { return len(r.lines) == 0 })
	time.Sleep(50 * time.Millisecond)
	got, ok := sub.Take()
	if !ok || got.Seq != 5 {
		t.Fatalf("Take = %+v, %v; want the seq 5 announcement", got, ok)
	}
	if _, ok := sub.Take(); ok {
		t.Fatal("the same announcement was taken twice")
	}
	if sub.Status().LastEventAt == nil {
		t.Fatal("no event time recorded")
	}

	// The relay goes away: the stream turns unhealthy once it stays down
	// past Grace, and the engine is woken to poll GitHub.
	close(r.hold)
	waitFor(t, "disconnect", func() bool { return !sub.Status().Connected })
	server.Close()
	select {
	case <-sub.Wake():
	case <-time.After(10 * time.Second):
		t.Fatal("no wake when the stream turned unhealthy")
	}
	if sub.Healthy() {
		t.Fatal("still healthy past the grace period")
	}
}

func TestPublish(t *testing.T) {
	var gotAuth, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		gotBody = string(body)
		if gotAuth != "Bearer tk_ok" {
			http.Error(w, `{"code":40301}`, http.StatusForbidden)
		}
	}))
	defer server.Close()

	if err := Publish(context.Background(), server.Client(), server.URL+"/dotfiles-rollout", "tk_ok", "hello"); err != nil {
		t.Fatal(err)
	}
	if gotBody != "hello" {
		t.Fatalf("body = %q", gotBody)
	}
	if err := Publish(context.Background(), server.Client(), server.URL+"/dotfiles-rollout", "tk_bad", "hello"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("err = %v, want the 403", err)
	}
}
