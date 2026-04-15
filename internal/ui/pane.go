// STUB: Minimal pane types for parallel slice development. Will be replaced by slice-3.
package ui

// Pane identifies a pane in the 4-pane layout.
type Pane int

const (
	PaneSlices  Pane = iota // Slice list (top-left)
	PaneDetail              // Detail view (top-center)
	PaneDeps                // Dependency graph (top-right)
	PaneActions             // Actions panel (bottom-left)
	PaneLogs                // Log viewer (bottom-right)
)
