package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/netip"
	"net/url"
	"time"

	"tailscale.com/tsnet"
)

// serveHTTP relays every request on ln to the forward's upstream over the
// tailnet, in TLS the relay opens itself, so clients that only take an HTTP
// base URL reach a tailnet HTTPS service. Requests are passed on unchanged
// apart from the Host header.
func serveHTTP(ln net.Listener, f forward, srv *tsnet.Server, up <-chan struct{}) error {
	target, err := url.Parse(f.Upstream)
	if err != nil {
		return err
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			ctx, cancel := context.WithTimeout(ctx, dialTimeout)
			defer cancel()
			return dialTailnet(ctx, srv, up, network, addr)
		},
		ForceAttemptHTTP2: true,
		MaxIdleConns:      100,
		IdleConnTimeout:   90 * time.Second,
		// The first handshake after the node starts waits for its path to
		// the peer, about 7 s from venus; net/http's default is 10 s.
		TLSHandshakeTimeout:   30 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
	proxy := &httputil.ReverseProxy{
		// SetURL also sets Host to the upstream's, which its ingress routes on.
		Rewrite:   func(r *httputil.ProxyRequest) { r.SetURL(target) },
		Transport: transport,
		// Model responses are event streams.
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("%s: %s %s: %v", f.Name, r.Method, r.URL.Path, err)
			http.Error(w, "tailnet-relay: "+err.Error(), http.StatusBadGateway)
		},
	}
	server := &http.Server{Handler: proxy, ReadHeaderTimeout: 30 * time.Second}
	return server.Serve(ln)
}

// dialTimeout bounds a dial, including the wait for the node to come up, so
// a node that cannot come up fails connections instead of holding them.
const dialTimeout = 30 * time.Second

// dialTailnet dials addr over the tailnet only, once the node is up: tsnet's
// Dial fails at once while the node is still starting. tsnet dials an
// address no peer it knows of serves through the host's own network instead,
// which it does for a Tailscale Service's address until the netmap names the
// peer that serves it, shortly after the node comes up. A connection that did
// not leave from the node's own address is closed before any byte is sent on
// it, and the dial is retried.
func dialTailnet(ctx context.Context, srv *tsnet.Server, up <-chan struct{}, network, addr string) (net.Conn, error) {
	select {
	case <-up:
	case <-ctx.Done():
		return nil, fmt.Errorf("tailnet is not up: %w", ctx.Err())
	}
	for {
		conn, err := srv.Dial(ctx, network, addr)
		if err == nil {
			if fromNode(srv, conn) {
				return conn, nil
			}
			conn.Close()
			err = errors.New("not routed over the tailnet yet")
		}
		select {
		case <-ctx.Done():
			return nil, fmt.Errorf("%s: %w", addr, err)
		case <-time.After(250 * time.Millisecond):
		}
	}
}

func fromNode(srv *tsnet.Server, conn net.Conn) bool {
	local, ok := conn.LocalAddr().(*net.TCPAddr)
	if !ok {
		return false
	}
	ip, ok := netip.AddrFromSlice(local.IP)
	if !ok {
		return false
	}
	v4, v6 := srv.TailscaleIPs()
	return ip.Unmap() == v4 || ip == v6
}
