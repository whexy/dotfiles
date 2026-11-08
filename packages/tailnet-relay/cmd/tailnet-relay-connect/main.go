// Command tailnet-relay-connect connects its standard input and output to a
// tailnet address through the relay's proxy, as an ssh ProxyCommand:
//
//	tailnet-relay-connect 127.0.0.1:47300 %h %p
//
// It refuses a proxy port this user does not hold: ssh trusts a new host's
// key on first use, so another user's proxy could otherwise stand in for
// the host, and take the forwarded agent.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"

	"golang.org/x/net/proxy"

	"github.com/whexy/dotfiles/packages/tailnet-relay/internal/held"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: tailnet-relay-connect 127.0.0.1:<port> <host> <port>")
		os.Exit(2)
	}
	if err := run(os.Args[1], net.JoinHostPort(os.Args[2], os.Args[3]), os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "tailnet-relay:", err)
		os.Exit(1)
	}
}

func run(proxyAddress, target string, in io.Reader, out io.Writer) error {
	if err := held.Check(proxyAddress, uint32(os.Getuid())); err != nil {
		return err
	}
	conn, err := net.Dial("tcp", proxyAddress)
	if err != nil {
		return err
	}
	defer conn.Close()
	dialer, err := proxy.SOCKS5("tcp", proxyAddress, nil, proxy.Direct)
	if err != nil {
		return err
	}
	// Over a connection of its own, which keeps CloseWrite.
	socks, ok := dialer.(interface {
		DialWithConn(context.Context, net.Conn, string, string) (net.Addr, error)
	})
	if !ok {
		return errors.New("the SOCKS5 dialer cannot dial over a given connection")
	}
	if _, err := socks.DialWithConn(context.Background(), conn, "tcp", target); err != nil {
		return err
	}

	go func() {
		io.Copy(conn, in)
		// The far end sees the end of input while its replies still arrive.
		conn.(*net.TCPConn).CloseWrite()
	}()
	_, err = io.Copy(out, conn)
	return err
}
