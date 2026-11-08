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

// openListeners takes each forward's listener from systemd socket
// activation, matched by FileDescriptorName, or binds it itself when the
// process was not socket-activated.
func openListeners(forwards []forward) (map[string]net.Listener, error) {
	activated, err := activatedListeners()
	if err != nil {
		return nil, err
	}
	listeners := map[string]net.Listener{}
	for _, f := range forwards {
		if activated != nil {
			ln, ok := activated[f.Name]
			if !ok {
				return nil, fmt.Errorf("forward %s: no socket named %q was passed", f.Name, f.Name)
			}
			if ln.Addr().String() != f.Listen {
				return nil, fmt.Errorf("forward %s: socket listens on %s, not %s", f.Name, ln.Addr(), f.Listen)
			}
			listeners[f.Name] = ln
			continue
		}
		ln, err := net.Listen("tcp", f.Listen)
		if err != nil {
			return nil, err
		}
		listeners[f.Name] = ln
	}
	for name, ln := range activated {
		if _, ok := listeners[name]; !ok {
			log.Printf("closing socket %q, which no forward names", name)
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
