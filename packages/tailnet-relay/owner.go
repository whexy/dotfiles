package main

import (
	"log"
	"net"
)

// ownerOnly admits only connections whose client socket belongs to uid.
//
// Every user on the host can reach a loopback port, and the relay speaks for
// its user's tailnet node, so it is the only gate between the host's other
// users and the tailnet. A connection is closed before any byte of it is
// read unless the kernel reports the client end as owned by uid. Anything
// running as uid is trusted, including a forwarder that others can reach.
type ownerOnly struct {
	net.Listener
	uid  uint32
	name string
}

func (l ownerOnly) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		owner, err := peerUID(conn)
		if err == nil && owner == l.uid {
			return conn, nil
		}
		if err != nil {
			log.Printf("%s: refused %s: %v", l.name, conn.RemoteAddr(), err)
		} else {
			log.Printf("%s: refused %s: owned by uid %d", l.name, conn.RemoteAddr(), owner)
		}
		conn.Close()
	}
}
