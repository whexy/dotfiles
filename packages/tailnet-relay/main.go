// Command tailnet-relay joins the tailnet as a userspace (tsnet) node and
// relays loopback connections from processes of its own user to tailnet
// services, on hosts that run no Tailscale daemon of their own.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"tailscale.com/envknob"
	"tailscale.com/tsnet"
)

type config struct {
	Hostname string `json:"hostname"`
	StateDir string `json:"stateDir"`
	// Read only while the node has no saved identity. Environment variables
	// in it are expanded, so it can name an agenix path.
	ClientSecretFile string    `json:"clientSecretFile"`
	Tags             []string  `json:"tags"`
	Forwards         []forward `json:"forwards"`
}

// A forward relays HTTP from a loopback listener to one tailnet origin.
type forward struct {
	Name     string `json:"name"`
	Listen   string `json:"listen"`
	Upstream string `json:"upstream"`
}

func main() {
	configPath := flag.String("config", "", "path of the JSON configuration")
	flag.Parse()
	if err := run(*configPath); err != nil {
		log.Fatal(err)
	}
}

func run(configPath string) error {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	// The node runs on hosts the owner does not control, so its logs stay
	// on the host instead of going to Tailscale's log service.
	envknob.SetNoLogsNoSupport()

	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		return err
	}
	// The node key in here is the node's tailnet identity.
	if err := os.Chmod(cfg.StateDir, 0o700); err != nil {
		return err
	}

	srv := &tsnet.Server{
		Hostname:      cfg.Hostname,
		Dir:           cfg.StateDir,
		AdvertiseTags: cfg.Tags,
		ClientSecret:  clientSecret(cfg.ClientSecretFile),
		UserLogf:      log.Printf,
	}
	defer srv.Close()

	listeners, err := openListeners(cfg.Forwards)
	if err != nil {
		return err
	}
	// A node that failed to come up never will, so the process exits and
	// systemd starts it again.
	errs := make(chan error, len(cfg.Forwards)+1)
	up := make(chan struct{})
	go func() {
		status, err := srv.Up(context.Background())
		if err != nil {
			errs <- fmt.Errorf("tailnet: %w", err)
			return
		}
		log.Printf("tailnet: up as %s", status.Self.DNSName)
		close(up)
	}()

	uid := uint32(os.Getuid())
	for _, f := range cfg.Forwards {
		ln := ownerOnly{Listener: listeners[f.Name], uid: uid, name: f.Name}
		go func() { errs <- fmt.Errorf("%s: %w", f.Name, serveHTTP(ln, f, srv, up)) }()
	}

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, os.Interrupt)
	select {
	case err := <-errs:
		return err
	case <-signals:
		return nil
	}
}

func loadConfig(path string) (*config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if cfg.Hostname == "" || cfg.StateDir == "" || len(cfg.Forwards) == 0 {
		return nil, fmt.Errorf("%s: hostname, stateDir and forwards are required", path)
	}
	seen := map[string]bool{}
	for _, f := range cfg.Forwards {
		if seen[f.Name] {
			return nil, fmt.Errorf("%s: forward %q is listed twice", path, f.Name)
		}
		seen[f.Name] = true
		host, _, err := net.SplitHostPort(f.Listen)
		if err != nil {
			return nil, fmt.Errorf("forward %s: %w", f.Name, err)
		}
		// The peer check only knows loopback peers.
		if ip := net.ParseIP(host); ip == nil || !ip.IsLoopback() {
			return nil, fmt.Errorf("forward %s: %s is not a loopback address", f.Name, f.Listen)
		}
		u, err := url.Parse(f.Upstream)
		if err != nil || u.Scheme != "https" || u.Host == "" || (u.Path != "" && u.Path != "/") {
			return nil, fmt.Errorf("forward %s: upstream must be an https:// origin, not %q", f.Name, f.Upstream)
		}
	}
	return &cfg, nil
}

// clientSecret is the OAuth client secret the node first joins with, as
// tsnet's oauthkey feature reads it: the minted key is preauthorized, and the
// node is kept while offline so its saved identity stays valid.
func clientSecret(path string) string {
	if path == "" {
		return ""
	}
	data, err := os.ReadFile(os.ExpandEnv(path))
	if err != nil {
		// A node that already joined does not need it.
		log.Printf("client secret: %v", err)
		return ""
	}
	secret := strings.TrimSpace(string(data))
	if secret == "" || strings.Contains(secret, "?") {
		return secret
	}
	return secret + "?ephemeral=false&preauthorized=true"
}
