// Package tmux is a thin exec wrapper around the tmux CLI.
package tmux

import (
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// Runner abstracts tmux invocation so hook logic is testable.
type Runner interface {
	// Run executes one tmux invocation (args may contain ";" separators
	// for multiple tmux commands) and returns trimmed stdout.
	Run(args ...string) (string, error)
}

// Exec is the real Runner.
type Exec struct{}

func (Exec) Run(args ...string) (string, error) {
	cmd := exec.Command("tmux", args...)
	// tmux replaces tabs in -F output with "_" outside a UTF-8 locale, which
	// would shred every field this package splits on.
	cmd.Env = append(os.Environ(), "LC_ALL="+utf8Locale())
	out, err := cmd.Output()
	// Trim only newlines: a TrimSpace would eat trailing tabs of the
	// last output line, i.e. trailing empty format fields.
	return strings.TrimRight(string(out), "\n"), err
}

// utf8Locale names a UTF-8 locale this platform actually has: Linux always
// ships C.UTF-8, macOS never does but always ships en_US.UTF-8. Naming a
// missing locale falls back to POSIX, which is what mangles the tabs.
func utf8Locale() string {
	if runtime.GOOS == "darwin" {
		return "en_US.UTF-8"
	}
	return "C.UTF-8"
}

// PaneOption reads a pane-scoped user option; empty string if unset.
func PaneOption(r Runner, pane, name string) string {
	out, err := r.Run("show-options", "-pqv", "-t", pane, name)
	if err != nil {
		return ""
	}
	return out
}
