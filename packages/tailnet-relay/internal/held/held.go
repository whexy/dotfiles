// Package held checks that a relay's loopback port is held by this user.
//
// The relay speaks plain HTTP on a port every user on the host can bind
// while the relay does not hold it, and a client that connected to such a
// listener would hand it its credentials and requests. The kernel names each
// listening socket's owner to every user, so a client checks before it
// connects.
package held

import (
	"fmt"
	"net"
	"sort"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"

	"github.com/whexy/dotfiles/packages/tailnet-relay/internal/sockdiag"
)

var loopback = net.IPv4(127, 0, 0, 1)

// Check fails unless every socket listening at address, which must be
// 127.0.0.1:<port>, belongs to uid.
func Check(address string, uid uint32) error {
	port, err := parse(address)
	if err != nil {
		return err
	}
	var sockets []sockdiag.Socket
	for _, family := range []uint8{unix.AF_INET, unix.AF_INET6} {
		listening, err := sockdiag.Listening(family)
		if err != nil {
			return err
		}
		sockets = append(sockets, listening...)
	}
	return check(address, port, uid, sockets)
}

func parse(address string) (uint16, error) {
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return 0, err
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if host != "127.0.0.1" || err != nil || port == 0 {
		return 0, fmt.Errorf("%s: only 127.0.0.1:<port> listeners can be checked", address)
	}
	return uint16(port), nil
}

func check(address string, port uint16, uid uint32, listening []sockdiag.Socket) error {
	owners := map[uint32]bool{}
	for _, s := range listening {
		// Wildcard and dual-stack listeners also take connections to
		// 127.0.0.1; IP.Equal matches ::ffff:127.0.0.1 too.
		if s.SPort == port && (s.Src.Equal(loopback) || s.Src.IsUnspecified()) {
			owners[s.UID] = true
		}
	}
	if len(owners) == 0 {
		return fmt.Errorf("nothing listens on %s; is the tailnet relay running?", address)
	}
	var strangers []string
	for owner := range owners {
		if owner != uid {
			strangers = append(strangers, strconv.FormatUint(uint64(owner), 10))
		}
	}
	if len(strangers) > 0 {
		sort.Strings(strangers)
		return fmt.Errorf("%s is held by uid %s, not this user; refusing to connect",
			address, strings.Join(strangers, ", "))
	}
	return nil
}
