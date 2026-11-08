// Package announce carries CI's verdict on a commit to the hosts. CI signs an
// Announcement and publishes it to an ntfy topic; each daemon subscribes,
// verifies the signature, and switches without asking GitHub. The relay is
// untrusted: it can delay or drop announcements, never forge one.
package announce

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// signingContext prefixes every signed payload, so a signature made for this
// purpose cannot be replayed as any other message signed with the same key.
const signingContext = "dotfiles-upgraded announcement v1\n"

// Announcement says that Sha, the tip of Ref in Repo, passed CI.
type Announcement struct {
	Repo string `json:"repo"`
	Ref  string `json:"ref"`
	Sha  string `json:"sha"`
	// Seq is the CI pipeline number, which grows with every pipeline the
	// repository starts. A host takes only an announcement with a higher Seq
	// than the last it took, so replaying an older one cannot roll it back.
	Seq  int64     `json:"seq"`
	Time time.Time `json:"time"`
}

type envelope struct {
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}

// ParsePrivateKey decodes a base64 ed25519 seed (32 bytes).
func ParsePrivateKey(b64 string) (ed25519.PrivateKey, error) {
	seed, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("signing key is not base64: %w", err)
	}
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("signing key is %d bytes, want a %d-byte ed25519 seed", len(seed), ed25519.SeedSize)
	}
	return ed25519.NewKeyFromSeed(seed), nil
}

// ParsePublicKey decodes a base64 ed25519 public key (32 bytes).
func ParsePublicKey(b64 string) (ed25519.PublicKey, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("public key is not base64: %w", err)
	}
	if len(raw) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("public key is %d bytes, want %d", len(raw), ed25519.PublicKeySize)
	}
	return ed25519.PublicKey(raw), nil
}

// Sign returns the message CI publishes for a.
func Sign(key ed25519.PrivateKey, a Announcement) (string, error) {
	if err := a.validate(); err != nil {
		return "", err
	}
	payload, err := json.Marshal(a)
	if err != nil {
		return "", err
	}
	sig := ed25519.Sign(key, append([]byte(signingContext), payload...))
	msg, err := json.Marshal(envelope{
		Payload:   base64.StdEncoding.EncodeToString(payload),
		Signature: base64.StdEncoding.EncodeToString(sig),
	})
	return string(msg), err
}

// Verify checks message against pub and returns the announcement it carries.
func Verify(pub ed25519.PublicKey, message string) (Announcement, error) {
	var env envelope
	if err := json.Unmarshal([]byte(message), &env); err != nil {
		return Announcement{}, fmt.Errorf("not an announcement: %w", err)
	}
	payload, err := base64.StdEncoding.DecodeString(env.Payload)
	if err != nil {
		return Announcement{}, fmt.Errorf("payload is not base64: %w", err)
	}
	sig, err := base64.StdEncoding.DecodeString(env.Signature)
	if err != nil {
		return Announcement{}, fmt.Errorf("signature is not base64: %w", err)
	}
	if !ed25519.Verify(pub, append([]byte(signingContext), payload...), sig) {
		return Announcement{}, errors.New("bad signature")
	}
	var a Announcement
	if err := json.Unmarshal(payload, &a); err != nil {
		return Announcement{}, fmt.Errorf("decode payload: %w", err)
	}
	return a, a.validate()
}

func (a Announcement) validate() error {
	switch {
	case a.Repo == "" || a.Ref == "":
		return errors.New("announcement names no repository or ref")
	case !isObjectID(a.Sha):
		return fmt.Errorf("announcement sha is not a commit: %.64q", a.Sha)
	case a.Seq <= 0:
		return fmt.Errorf("announcement seq %d is not positive", a.Seq)
	}
	return nil
}

// isObjectID reports whether s is a full SHA-1 or SHA-256 hex object name; the
// sha ends up in the flake ref the host builds.
func isObjectID(s string) bool {
	if len(s) != 40 && len(s) != 64 {
		return false
	}
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}
