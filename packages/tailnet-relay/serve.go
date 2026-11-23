package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"time"

	"tailscale.com/tsnet"
)

// A serve accepts TCP on a port of the node's tailnet addresses and relays
// each connection to a loopback address of this host, so a service of the
// host, such as sshd, is reachable from the tailnet although the host is
// not on it.
type serve struct {
	Name   string `json:"name"`
	Port   uint16 `json:"port"`
	Target string `json:"target"`
	// TLS ends TLS on the port with the node's MagicDNS certificate and
	// relays the plaintext, so a plain HTTP service is served as
	// https://<node>:<port>, as Tailscale Serve would serve it.
	TLS bool `json:"tls"`
}

// serveTailnet relays connections to s.Port of the node to s.Target. The
// tailnet policy is the only gate in front of the target, so the target's
// own protocol has to authenticate callers.
func serveTailnet(srv *tsnet.Server, s serve) error {
	listen := srv.Listen
	if s.TLS {
		// Waits for the node to come up, which knows its certificate's name.
		listen = srv.ListenTLS
	}
	ln, err := listen("tcp", fmt.Sprintf(":%d", s.Port))
	if err != nil {
		return err
	}
	defer ln.Close()
	for {
		conn, err := ln.Accept()
		if err != nil {
			return err
		}
		go relayInbound(srv, s, conn)
	}
}

func relayInbound(srv *tsnet.Server, s serve, conn net.Conn) {
	defer conn.Close()
	// The target sees every caller as loopback, so the relay's log is the
	// only record of which tailnet node connected.
	log.Printf("%s: %s", s.Name, caller(srv, conn))
	target, err := net.DialTimeout("tcp", s.Target, 10*time.Second)
	if err != nil {
		log.Printf("%s: %v", s.Name, err)
		return
	}
	defer target.Close()
	pipe(conn, target)
}

// caller names the tailnet node and user behind conn, as far as the node's
// view of the tailnet knows them.
func caller(srv *tsnet.Server, conn net.Conn) string {
	from := conn.RemoteAddr().String()
	lc, err := srv.LocalClient()
	if err != nil {
		return from
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	who, err := lc.WhoIs(ctx, from)
	if err != nil || who.Node == nil {
		return from
	}
	if who.UserProfile != nil && who.UserProfile.LoginName != "" {
		return fmt.Sprintf("%s (%s, %s)", from, who.Node.ComputedName, who.UserProfile.LoginName)
	}
	return fmt.Sprintf("%s (%s)", from, who.Node.ComputedName)
}

// pipe copies a and b into each other until both directions end. A clean
// end of one direction is passed on as a half-close; an error ends both.
func pipe(a, b net.Conn) {
	errs := make(chan error, 2)
	copyTo := func(dst, src net.Conn) {
		_, err := io.Copy(dst, src)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok && err == nil {
			cw.CloseWrite()
		} else {
			dst.Close()
		}
		errs <- err
	}
	go copyTo(a, b)
	go copyTo(b, a)
	if err := <-errs; err != nil && !errors.Is(err, net.ErrClosed) {
		a.Close()
		b.Close()
	}
	<-errs
}
