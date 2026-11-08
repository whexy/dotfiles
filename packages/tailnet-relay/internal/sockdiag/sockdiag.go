// Package sockdiag asks Linux (NETLINK_SOCK_DIAG) about TCP sockets and the
// users that own them, which every user may ask about every socket.
package sockdiag

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"

	"golang.org/x/sys/unix"
)

// Sizes and offsets of <linux/inet_diag.h>: inet_diag_req_v2 is an 8-byte
// header and a 48-byte inet_diag_sockid; inet_diag_msg's idiag_uid follows
// its 4-byte header, the sockid, and three 32-bit fields.
const (
	nlmsgHeaderLen = 16
	sockIDLen      = 48
	reqLen         = 8 + sockIDLen
	msgUIDOff      = 4 + sockIDLen + 12
	tcpListen      = 10
)

// Socket is one TCP socket: its local end (Src), its peer (Dst), and owner.
type Socket struct {
	Src   net.IP
	SPort uint16
	Dst   net.IP
	DPort uint16
	UID   uint32
}

// Owner is the owner of the socket whose local end is src and whose peer is
// dst.
func Owner(src, dst *net.TCPAddr) (uint32, error) {
	family, srcIP, dstIP := uint8(unix.AF_INET6), src.IP.To16(), dst.IP.To16()
	if src.IP.To4() != nil && dst.IP.To4() != nil {
		family, srcIP, dstIP = unix.AF_INET, src.IP.To4(), dst.IP.To4()
	}
	sockets, err := query(family, 0xffffffff, unix.NLM_F_REQUEST, func(id []byte) {
		binary.BigEndian.PutUint16(id[0:], uint16(src.Port))
		binary.BigEndian.PutUint16(id[2:], uint16(dst.Port))
		copy(id[4:20], srcIP)
		copy(id[20:36], dstIP)
	})
	if err != nil {
		return 0, err
	}
	if len(sockets) == 0 {
		return 0, errors.New("sock_diag: socket not found")
	}
	return sockets[0].UID, nil
}

// Listening is every listening TCP socket of the address family.
func Listening(family uint8) ([]Socket, error) {
	return query(family, 1<<tcpListen, unix.NLM_F_REQUEST|unix.NLM_F_DUMP, func([]byte) {})
}

func query(family uint8, states uint32, flags uint16, setID func([]byte)) ([]Socket, error) {
	fd, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_DGRAM|unix.SOCK_CLOEXEC, unix.NETLINK_SOCK_DIAG)
	if err != nil {
		return nil, fmt.Errorf("sock_diag: %w", err)
	}
	defer unix.Close(fd)
	timeout := unix.Timeval{Sec: 2}
	if err := unix.SetsockoptTimeval(fd, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &timeout); err != nil {
		return nil, fmt.Errorf("sock_diag: %w", err)
	}

	native := binary.NativeEndian
	msg := make([]byte, nlmsgHeaderLen+reqLen)
	native.PutUint32(msg[0:], uint32(len(msg)))
	native.PutUint16(msg[4:], unix.SOCK_DIAG_BY_FAMILY)
	native.PutUint16(msg[6:], flags)
	native.PutUint32(msg[8:], 1)
	req := msg[nlmsgHeaderLen:]
	req[0] = family
	req[1] = unix.IPPROTO_TCP
	native.PutUint32(req[4:], states)
	id := req[8:]
	setID(id)
	// INET_DIAG_NOCOOKIE: match by address alone.
	native.PutUint32(id[40:], 0xffffffff)
	native.PutUint32(id[44:], 0xffffffff)
	if err := unix.Sendto(fd, msg, 0, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		return nil, fmt.Errorf("sock_diag: %w", err)
	}

	var sockets []Socket
	buf := make([]byte, 8*os.Getpagesize())
	for {
		n, _, err := unix.Recvfrom(fd, buf, 0)
		if err != nil {
			return nil, fmt.Errorf("sock_diag: %w", err)
		}
		for data := buf[:n]; len(data) >= nlmsgHeaderLen; {
			size := int(native.Uint32(data[0:]))
			if size < nlmsgHeaderLen || size > len(data) {
				return nil, errors.New("sock_diag: malformed reply")
			}
			body := data[nlmsgHeaderLen:size]
			switch native.Uint16(data[4:]) {
			case unix.NLMSG_DONE:
				return sockets, nil
			case unix.NLMSG_ERROR:
				if len(body) >= 4 {
					if errno := int32(native.Uint32(body)); errno != 0 {
						if unix.Errno(-errno) == unix.ENOENT {
							return nil, nil
						}
						return nil, fmt.Errorf("sock_diag: %w", unix.Errno(-errno))
					}
				}
				return sockets, nil
			case unix.SOCK_DIAG_BY_FAMILY:
				if len(body) < msgUIDOff+4 {
					return nil, errors.New("sock_diag: short reply")
				}
				sockets = append(sockets, parse(body))
			}
			data = data[(size+3)&^3:]
		}
		if flags&unix.NLM_F_DUMP == 0 {
			return sockets, nil
		}
	}
}

func parse(msg []byte) Socket {
	id := msg[4:]
	ipLen := net.IPv6len
	if msg[0] == unix.AF_INET {
		ipLen = net.IPv4len
	}
	return Socket{
		SPort: binary.BigEndian.Uint16(id[0:]),
		DPort: binary.BigEndian.Uint16(id[2:]),
		Src:   net.IP(append([]byte(nil), id[4:4+ipLen]...)),
		Dst:   net.IP(append([]byte(nil), id[20:20+ipLen]...)),
		UID:   binary.NativeEndian.Uint32(msg[msgUIDOff:]),
	}
}
