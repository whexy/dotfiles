package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"

	"golang.org/x/sys/unix"
)

// Sizes and offsets of <linux/inet_diag.h>: inet_diag_req_v2 is a 8-byte
// header and a 48-byte inet_diag_sockid; inet_diag_msg's idiag_uid follows
// its 4-byte header, the sockid, and three 32-bit fields.
const (
	nlmsgHeaderLen = 16
	diagSockIDLen  = 48
	diagReqLen     = 8 + diagSockIDLen
	diagMsgUIDOff  = 4 + diagSockIDLen + 12
)

// peerUID asks the kernel (NETLINK_SOCK_DIAG) which user owns the client
// end of a loopback TCP connection: the socket whose local address is the
// connection's remote address, connected to its local address.
func peerUID(conn net.Conn) (uint32, error) {
	local, ok := conn.LocalAddr().(*net.TCPAddr)
	remote, ok2 := conn.RemoteAddr().(*net.TCPAddr)
	if !ok || !ok2 {
		return 0, errors.New("not a TCP connection")
	}
	family, src, dst := uint8(unix.AF_INET6), remote.IP.To16(), local.IP.To16()
	if remote.IP.To4() != nil && local.IP.To4() != nil {
		family, src, dst = unix.AF_INET, remote.IP.To4(), local.IP.To4()
	}

	fd, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_DGRAM|unix.SOCK_CLOEXEC, unix.NETLINK_SOCK_DIAG)
	if err != nil {
		return 0, fmt.Errorf("sock_diag: %w", err)
	}
	defer unix.Close(fd)
	timeout := unix.Timeval{Sec: 2}
	if err := unix.SetsockoptTimeval(fd, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &timeout); err != nil {
		return 0, fmt.Errorf("sock_diag: %w", err)
	}

	native := binary.NativeEndian
	msg := make([]byte, nlmsgHeaderLen+diagReqLen)
	native.PutUint32(msg[0:], uint32(len(msg)))
	native.PutUint16(msg[4:], unix.SOCK_DIAG_BY_FAMILY)
	native.PutUint16(msg[6:], unix.NLM_F_REQUEST)
	native.PutUint32(msg[8:], 1)
	req := msg[nlmsgHeaderLen:]
	req[0] = family
	req[1] = unix.IPPROTO_TCP
	native.PutUint32(req[4:], 0xffffffff) // every TCP state
	id := req[8:]
	binary.BigEndian.PutUint16(id[0:], uint16(remote.Port))
	binary.BigEndian.PutUint16(id[2:], uint16(local.Port))
	copy(id[4:20], src)
	copy(id[20:36], dst)
	// INET_DIAG_NOCOOKIE: match by address alone.
	native.PutUint32(id[40:], 0xffffffff)
	native.PutUint32(id[44:], 0xffffffff)

	if err := unix.Sendto(fd, msg, 0, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		return 0, fmt.Errorf("sock_diag: %w", err)
	}
	buf := make([]byte, os.Getpagesize())
	n, _, err := unix.Recvfrom(fd, buf, 0)
	if err != nil {
		return 0, fmt.Errorf("sock_diag: %w", err)
	}
	if n < nlmsgHeaderLen {
		return 0, errors.New("sock_diag: short reply")
	}
	switch native.Uint16(buf[4:]) {
	case unix.NLMSG_ERROR:
		if n >= nlmsgHeaderLen+4 {
			if errno := int32(native.Uint32(buf[nlmsgHeaderLen:])); errno != 0 {
				return 0, fmt.Errorf("sock_diag: client socket: %w", unix.Errno(-errno))
			}
		}
		return 0, errors.New("sock_diag: client socket not found")
	case unix.SOCK_DIAG_BY_FAMILY:
		if n < nlmsgHeaderLen+diagMsgUIDOff+4 {
			return 0, errors.New("sock_diag: short reply")
		}
		return native.Uint32(buf[nlmsgHeaderLen+diagMsgUIDOff:]), nil
	default:
		return 0, fmt.Errorf("sock_diag: unexpected reply type %d", native.Uint16(buf[4:]))
	}
}
