// Package commit validates the commit names the daemon receives from GitHub
// and from announcements before they reach a flake ref or an API path.
package commit

// IsObjectID reports whether s is a full SHA-1 or SHA-256 hex object name.
func IsObjectID(s string) bool {
	if len(s) != 40 && len(s) != 64 {
		return false
	}
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}
