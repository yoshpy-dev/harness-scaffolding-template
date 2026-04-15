// STUB: Shared UI messages for parallel slice development. Will be replaced by slice-3/4.
package ui

import "github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/state"

// SliceSelectedMsg is sent when a slice is selected in the slice list pane.
type SliceSelectedMsg struct {
	Slice *state.SliceState
}

// StatusMsg is sent to display a status message in the status bar.
type StatusMsg struct {
	Text    string
	IsError bool
}
