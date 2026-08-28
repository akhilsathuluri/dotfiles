package ui

import (
	"testing"

	"github.com/charmbracelet/lipgloss"

	"github.com/abhishekrana/agentbar/internal/model"
)

// The five-state language: permission is a hard red block, distinct from the amber ask.
func TestStateColorFiveStates(t *testing.T) {
	th := SolarizedLight()
	want := map[model.AgentState]lipgloss.Color{
		model.StateWorking:    th.Working,
		model.StatePermission: th.Blocked,
		model.StateQuestion:   th.Asking,
		model.StateDone:       th.Done,
		model.StateIdle:       th.Muted,
	}
	for st, w := range want {
		if got := th.StateColor(st); got != w {
			t.Errorf("StateColor(%q) = %v, want %v", st, got, w)
		}
	}
	// Regression on the old amber==amber: blocked and asking must be distinct.
	if th.Blocked == th.Asking {
		t.Error("blocked and asking must be distinct colors")
	}
}

// All four flavors resolve; unknown/empty falls back to palette.toml's [meta] default.
func TestThemeByNameFlavors(t *testing.T) {
	if ThemeByName("catppuccin-mocha").Working != CatppuccinMocha().Working {
		t.Error("catppuccin-mocha should resolve to the Mocha palette")
	}
	if ThemeByName("solarized-dark").SelBg != SolarizedDark().SelBg {
		t.Error("solarized-dark should resolve to the Solarized Dark palette")
	}
	if ThemeByName("solarized-light").SelBg != SolarizedLight().SelBg {
		t.Error("solarized-light should resolve to the Solarized Light palette")
	}
	if ThemeByName("catppuccin-latte").Accent != CatppuccinLatte().Accent {
		t.Error("catppuccin-latte should resolve to the Latte palette")
	}
	// Compare a token the flavors do not share: Solarized Light and Dark carry the
	// same accent, so an accent check passed even while the fallback was wrong.
	for _, name := range []string{"nonesuch", ""} {
		if ThemeByName(name).SelBg != SolarizedDark().SelBg {
			t.Errorf("ThemeByName(%q) should fall back to the default flavor", name)
		}
	}
}

// The black variant is Mocha with the indigo taken out of the ground: same content and
// accent hues, neutral greys. A palette edit that tinted those greys would undo it.
func TestCatppuccinMochaBlackIsNeutralMocha(t *testing.T) {
	black, mocha := CatppuccinMochaBlack(), CatppuccinMocha()
	for _, c := range []struct{ name, got, want string }{
		{"Fg", string(black.Fg), string(mocha.Fg)},
		{"Accent", string(black.Accent), string(mocha.Accent)},
		{"Working", string(black.Working), string(mocha.Working)},
		{"Asking", string(black.Asking), string(mocha.Asking)},
		{"Blocked", string(black.Blocked), string(mocha.Blocked)},
		{"Done", string(black.Done), string(mocha.Done)},
	} {
		if c.got != c.want {
			t.Errorf("%s = %s, want Mocha's %s", c.name, c.got, c.want)
		}
	}
	// SelBg is the one surface the sidebar paints, so it is the one that must be grey.
	sel := string(black.SelBg)
	if len(sel) != 7 || sel[1:3] != sel[3:5] || sel[3:5] != sel[5:7] {
		t.Errorf("SelBg = %s, want a neutral grey (R=G=B)", sel)
	}
}
