package main

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"

	"tailscale.com/net/socks5"
)

func listen(t *testing.T) net.Listener {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	return ln
}

// The reply that follows the end of input still arrives.
func TestRunRelaysBothWays(t *testing.T) {
	echo := listen(t)
	go func() {
		conn, err := echo.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		data, _ := io.ReadAll(conn)
		conn.Write(bytes.ToUpper(data))
	}()
	proxy := listen(t)
	go (&socks5.Server{}).Serve(proxy)

	var out bytes.Buffer
	if err := run(proxy.Addr().String(), echo.Addr().String(), strings.NewReader("hello"), &out); err != nil {
		t.Fatal(err)
	}
	if out.String() != "HELLO" {
		t.Fatalf("got %q", out.String())
	}
}

func TestRunRefusesFreePort(t *testing.T) {
	ln := listen(t)
	address := ln.Addr().String()
	ln.Close()
	if err := run(address, "127.0.0.1:1", strings.NewReader(""), io.Discard); err == nil {
		t.Fatal("connected through a port nothing holds")
	}
}
