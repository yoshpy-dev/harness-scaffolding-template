package ui

import "charm.land/lipgloss/v2"

// Color constants used across the TUI.
var (
	ColorFocusBorder   = lipgloss.Color("62")  // purple
	ColorNormalBorder   = lipgloss.Color("240") // gray
	ColorTitle          = lipgloss.Color("170") // pink
	ColorStatusOK       = lipgloss.Color("42")  // green
	ColorStatusFail     = lipgloss.Color("196") // red
	ColorStatusRunning  = lipgloss.Color("214") // orange
	ColorStatusPending  = lipgloss.Color("245") // dim gray
	ColorProgress       = lipgloss.Color("62")  // purple
)

// PaneStyle returns the border style for a pane.
// width and height are the content dimensions (border adds 2 to each).
func PaneStyle(focused bool, width, height int) lipgloss.Style {
	c := ColorNormalBorder
	if focused {
		c = ColorFocusBorder
	}
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(c).
		Width(width).
		Height(height)
}

// TitleStyle returns the style for pane titles.
func TitleStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Bold(true).
		Foreground(ColorTitle)
}

// StatusStyle returns a style colored by status.
func StatusStyle(status string) lipgloss.Style {
	switch status {
	case "complete", "passed":
		return lipgloss.NewStyle().Foreground(ColorStatusOK)
	case "failed", "error":
		return lipgloss.NewStyle().Foreground(ColorStatusFail)
	case "running":
		return lipgloss.NewStyle().Foreground(ColorStatusRunning)
	default:
		return lipgloss.NewStyle().Foreground(ColorStatusPending)
	}
}

// HelpOverlayStyle returns the style for the help overlay box.
func HelpOverlayStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(ColorFocusBorder).
		Padding(1, 2)
}
