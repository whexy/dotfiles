// Command tailnet-relay-check exits non-zero unless this user holds every
// relay address given, so a client can check before it connects.
//
//	tailnet-relay-check 127.0.0.1:47301 [...]
package main

import (
	"fmt"
	"os"

	"github.com/whexy/dotfiles/packages/tailnet-relay/internal/held"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: tailnet-relay-check 127.0.0.1:<port> ...")
		os.Exit(2)
	}
	uid := uint32(os.Getuid())
	for _, address := range os.Args[1:] {
		if err := held.Check(address, uid); err != nil {
			fmt.Fprintln(os.Stderr, "tailnet-relay:", err)
			os.Exit(1)
		}
	}
}
