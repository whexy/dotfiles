package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"syscall"
)

// openListeners takes the listener for each name's address from systemd
// socket activation, matched by FileDescriptorName, or binds it itself when
// the process was not socket-activated.
func openListeners(addresses map[string]string) (map[string]net.Listener, error) {
	activated, err := activatedListeners()
	if err != nil {
		return nil, err
	}
	listeners := map[string]net.Listener{}
	for name, address := range addresses {
		if activated != nil {
			ln, ok := activated[name]
			if !ok {
				return nil, fmt.Errorf("%s: no socket named %q was passed", name, name)
			}
			if ln.Addr().String() != address {
				return nil, fmt.Errorf("%s: socket listens on %s, not %s", name, ln.Addr(), address)
			}
			listeners[name] = ln
			continue
		}
		ln, err := net.Listen("tcp", address)
		if err != nil {
			return nil, err
		}
		listeners[name] = ln
	}
	for name, ln := range activated {
		if _, ok := listeners[name]; !ok {
			log.Printf("closing socket %q, which the configuration does not name", name)
			ln.Close()
		}
	}
	return listeners, nil
}

// activatedListeners implements sd_listen_fds(3) with names; nil when the
// process was not socket-activated.
func activatedListeners() (map[string]net.Listener, error) {
	if os.Getenv("LISTEN_PID") != strconv.Itoa(os.Getpid()) {
		return nil, nil
	}
	count, err := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	if err != nil {
		return nil, fmt.Errorf("LISTEN_FDS: %w", err)
	}
	names := strings.Split(os.Getenv("LISTEN_FDNAMES"), ":")
	for _, key := range []string{"LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"} {
		os.Unsetenv(key)
	}
	listeners := map[string]net.Listener{}
	for i := range count {
		fd := 3 + i
		syscall.CloseOnExec(fd)
		name := strconv.Itoa(fd)
		if i < len(names) && names[i] != "" {
			name = names[i]
		}
		file := os.NewFile(uintptr(fd), name)
		ln, err := net.FileListener(file)
		file.Close()
		if err != nil {
			return nil, fmt.Errorf("socket %s: %w", name, err)
		}
		listeners[name] = ln
	}
	return listeners, nil
}
