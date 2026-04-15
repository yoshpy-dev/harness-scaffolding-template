// STUB: Minimal types for parallel slice development. Will be replaced by slice-1.
package state

// SliceStatus represents the status of a pipeline slice.
type SliceStatus string

const (
	StatusPending  SliceStatus = "pending"
	StatusRunning  SliceStatus = "running"
	StatusComplete SliceStatus = "complete"
	StatusFailed   SliceStatus = "failed"
	StatusStuck    SliceStatus = "stuck"
	StatusAborted  SliceStatus = "aborted"
)

// SliceState holds the state of a single slice.
type SliceState struct {
	Name         string      `json:"name"`
	Status       SliceStatus `json:"status"`
	Phase        string      `json:"phase"`
	LogPath      string      `json:"log_path"`
	WorktreePath string      `json:"worktree_path"`
}

// CanRetry returns true if the slice is in a state that supports retry.
func (s *SliceState) CanRetry() bool {
	return s.Status == StatusFailed || s.Status == StatusStuck
}

// CanAbort returns true if the slice is in a state that supports abort.
func (s *SliceState) CanAbort() bool {
	return s.Status == StatusRunning || s.Status == StatusFailed || s.Status == StatusStuck
}

// HasLogs returns true if the slice has a log path.
func (s *SliceState) HasLogs() bool {
	return s.LogPath != ""
}

// HasWorktree returns true if the slice has a worktree path.
func (s *SliceState) HasWorktree() bool {
	return s.WorktreePath != ""
}
