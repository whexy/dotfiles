package main

import (
	"context"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"time"

	"tailscale.com/tsnet"
)

// serveHTTP relays every request on ln to the forward's upstream over the
// tailnet, in TLS the relay opens itself, so clients that only take an HTTP
// base URL reach a tailnet HTTPS service. Requests are passed on unchanged
// apart from the Host header.
func serveHTTP(ln net.Listener, f forward, srv *tsnet.Server) error {
	target, err := url.Parse(f.Upstream)
	if err != nil {
		return err
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// tsnet waits for the node to come up; a node that cannot fails
			// the request instead of holding it.
			ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
			defer cancel()
			return srv.Dial(ctx, network, addr)
		},
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
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
