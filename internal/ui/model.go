package ui

import (
	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"
)

// Model is the root Bubble Tea model for ralph-tui.
type Model struct {
	Width    int
	Height   int
	Focused  Pane
	ShowHelp bool
	Keys     KeyMap
	Panes    PaneContents
	Quitting bool
}

// New creates a new Model with placeholder pane contents.
func New() Model {
	return Model{
		Focused: PaneSlices,
		Keys:    DefaultKeyMap(),
		Panes: PaneContents{
			Slices:  "Slices (placeholder)",
			Detail:  "Detail (placeholder)",
			Deps:    "Dependencies (placeholder)",
			Actions: "Actions (placeholder)",
			Logs:    "Logs (placeholder)",
		},
	}
}

// Init initializes the model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles incoming messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		return m, nil

	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}

	return m, nil
}

// handleKey processes key press events.
func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	// When help overlay is shown, only ? and q are active.
	if m.ShowHelp {
		switch {
		case key.Matches(msg, m.Keys.Help):
			m.ShowHelp = false
		case key.Matches(msg, m.Keys.Quit):
			m.Quitting = true
			return m, tea.Quit
		}
		return m, nil
	}

	switch {
	case key.Matches(msg, m.Keys.Quit):
		m.Quitting = true
		return m, tea.Quit
	case key.Matches(msg, m.Keys.Help):
		m.ShowHelp = true
	case key.Matches(msg, m.Keys.Left):
		m.Focused = LeftPane(m.Focused)
	case key.Matches(msg, m.Keys.Right):
		m.Focused = RightPane(m.Focused)
	case key.Matches(msg, m.Keys.NextPane):
		m.Focused = NextPane(m.Focused)
	case key.Matches(msg, m.Keys.PrevPane):
		m.Focused = PrevPane(m.Focused)
	}

	return m, nil
}

// View renders the UI.
func (m Model) View() tea.View {
	if m.Quitting {
		return tea.NewView("")
	}
	if m.Width == 0 || m.Height == 0 {
		return tea.NewView("Initializing...")
	}

	if m.ShowHelp {
		return tea.NewView(RenderHelp(m.Width, m.Height))
	}

	progress := " Progress: 0/0 (0%)"
	return tea.NewView(RenderLayout(m.Width, m.Height, m.Panes, m.Focused, progress))
}
