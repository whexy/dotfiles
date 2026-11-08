package main

import (
	"context"
	"fmt"
	"log"
	"net"

	"tailscale.com/net/socks5"
	"tailscale.com/tsnet"
)

// serveProxy serves SOCKS5 on ln, connecting to tailnet addresses, for
// clients of protocols other than HTTP. Their own protocol has to
// authenticate the far end: a client cannot tell this proxy from one another
// user put on its port unless it runs tailnet-relay-check first.
func serveProxy(ln net.Listener, srv *tsnet.Server, up <-chan struct{}) error {
	proxy := &socks5.Server{
		Logf: func(format string, args ...any) { log.Printf(proxyName+": "+format, args...) },
		Dialer: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// UDP ASSOCIATE relays from a loopback UDP socket that admits
			// datagrams from any user, so nothing but TCP is dialed.
			if network != "tcp" {
				return nil, fmt.Errorf("%s is not relayed", network)
			}
			// socks5 gives a dial 5 s, less than the first connection to a
			// peer can take after the node starts.
			ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), dialTimeout)
			defer cancel()
			return dialTailnet(ctx, srv, up, network, addr)
		},
	}
	return proxy.Serve(ln)
}
