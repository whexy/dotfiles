package held

import (
	"fmt"
	"net"
	"os"
	"strings"
	"testing"

	"github.com/whexy/dotfiles/packages/tailnet-relay/internal/sockdiag"
)

func TestCheck(t *testing.T) {
	const port = 47301
	socket := func(ip string, port uint16, uid uint32) sockdiag.Socket {
		return sockdiag.Socket{Src: net.ParseIP(ip), SPort: port, UID: uid}
	}
	cases := []struct {
		name      string
		listening []sockdiag.Socket
		want      string
	}{
		{"own loopback listener", []sockdiag.Socket{socket("127.0.0.1", port, 1000)}, ""},
		{"nothing listens", []sockdiag.Socket{socket("127.0.0.1", port+1, 1000)}, "nothing listens"},
		{"other user's loopback listener", []sockdiag.Socket{socket("127.0.0.1", port, 1001)}, "uid 1001"},
		{"other user's wildcard listener", []sockdiag.Socket{socket("0.0.0.0", port, 1001)}, "uid 1001"},
		{"other user's dual-stack listener", []sockdiag.Socket{socket("::", port, 1001)}, "uid 1001"},
		{"other user's mapped loopback listener", []sockdiag.Socket{socket("::ffff:127.0.0.1", port, 1001)}, "uid 1001"},
		{"other user beside the relay", []sockdiag.Socket{socket("127.0.0.1", port, 1000), socket("0.0.0.0", port, 1001)}, "uid 1001"},
		{"other user on another loopback address", []sockdiag.Socket{socket("127.0.0.1", port, 1000), socket("127.0.0.2", port, 1001)}, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := check("127.0.0.1:47301", port, 1000, c.listening)
			switch {
			case c.want == "" && err != nil:
				t.Fatalf("unexpected error: %v", err)
			case c.want != "" && (err == nil || !strings.Contains(err.Error(), c.want)):
				t.Fatalf("error %v, want one containing %q", err, c.want)
			}
		})
	}
}

func TestCheckRejectsOtherAddresses(t *testing.T) {
	for _, address := range []string{"localhost:47301", "0.0.0.0:47301", "[::1]:47301", "127.0.0.1:0"} {
		if err := Check(address, 1000); err == nil {
			t.Errorf("%s accepted", address)
		}
	}
}

func TestCheckRealListener(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	uid := uint32(os.Getuid())
	if err := Check(ln.Addr().String(), uid); err != nil {
		t.Fatal(err)
	}
	if err := Check(ln.Addr().String(), uid+1); err == nil {
		t.Fatal("own listener accepted for another uid")
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	if err := Check(fmt.Sprintf("127.0.0.1:%d", port), uid); err == nil {
		t.Fatal("closed listener accepted")
	}
}
