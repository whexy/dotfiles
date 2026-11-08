package main

import (
	"errors"
	"net"

	"github.com/whexy/dotfiles/packages/tailnet-relay/internal/sockdiag"
)

// peerUID is the owner of the client end of a loopback TCP connection: the
// socket whose local address is the connection's remote address, connected
// to its local address.
func peerUID(conn net.Conn) (uint32, error) {
	local, ok := conn.LocalAddr().(*net.TCPAddr)
	remote, ok2 := conn.RemoteAddr().(*net.TCPAddr)
	if !ok || !ok2 {
		return 0, errors.New("not a TCP connection")
	}
	return sockdiag.Owner(remote, local)
}
