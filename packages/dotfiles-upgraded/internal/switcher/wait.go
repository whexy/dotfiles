package switcher

import (
	"errors"
	"syscall"
	"unsafe"
)

// waitForExit observes the leader without reaping it. Keeping its PID reserved
// prevents a later process group from inheriting the ID while descendants hold
// the output pipes. Linux and Darwin both provide waitid with P_PID = 1.
func waitForExit(pid int) error {
	// siginfo_t fits in 128 bytes on Linux and Darwin; its fields are not needed.
	var info [16]uint64
	for {
		_, _, errno := syscall.Syscall6(syscall.SYS_WAITID, 1, uintptr(pid), uintptr(unsafe.Pointer(&info[0])), syscall.WEXITED|syscall.WNOWAIT, 0, 0)
		if errors.Is(errno, syscall.EINTR) {
			continue
		}
		if errno != 0 {
			return errno
		}
		return nil
	}
}
