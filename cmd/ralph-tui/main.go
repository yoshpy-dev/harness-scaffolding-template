package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	tea "charm.land/bubbletea/v2"

	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/action"
	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/state"
	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/ui"
	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/watcher"
)

func main() {
	orchDir := flag.String("orch-dir", "", "path to orchestrator state directory")
	worktreeBase := flag.String("worktree-base", "", "path to worktree base directory")
	planDir := flag.String("plan-dir", "", "path to plan directory (for dependency graph)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(versionString())
		os.Exit(0)
	}

	if *orchDir == "" {
		log.Fatal("--orch-dir is required")
	}
	if *worktreeBase == "" {
		log.Fatal("--worktree-base is required")
	}

	// Resolve to absolute paths for reliable file watching.
	absOrchDir, err := filepath.Abs(*orchDir)
	if err != nil {
		log.Fatalf("resolving orch-dir: %v", err)
	}
	absWorktreeBase, err := filepath.Abs(*worktreeBase)
	if err != nil {
		log.Fatalf("resolving worktree-base: %v", err)
	}

	absPlanDir := ""
	if *planDir != "" {
		absPlanDir, err = filepath.Abs(*planDir)
		if err != nil {
			log.Fatalf("resolving plan-dir: %v", err)
		}
	}

	// Read initial state.
	status, err := state.ReadFullStatus(absOrchDir, absWorktreeBase, absPlanDir)
	if err != nil {
		log.Fatalf("reading initial state: %v", err)
	}

	// Create file watcher.
	w, err := watcher.New(absOrchDir, absWorktreeBase)
	if err != nil {
		log.Fatalf("creating watcher: %v", err)
	}
	defer func() { _ = w.Stop() }()

	// Create action executor (repo root is two levels up from orch-dir:
	// .harness/state/loop/ → repo root).
	repoRoot := resolveRepoRoot(absOrchDir)
	var executor *action.Executor
	if exec, err := action.NewExecutor(repoRoot); err == nil {
		executor = exec
	}

	// Build the TUI model.
	model := newAppModel(status, w, executor, absOrchDir, absWorktreeBase, absPlanDir)

	p := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		log.Fatalf("TUI error: %v", err)
	}
}

// resolveRepoRoot walks up from orchDir to find the repo root.
// orchDir is typically .harness/state/loop/ so we go up 3 levels.
func resolveRepoRoot(orchDir string) string {
	// Try going up from the orch dir until we find .git or scripts/ralph
	dir := orchDir
	for range 10 {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return dir
		}
		if _, err := os.Stat(filepath.Join(dir, "scripts", "ralph")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	// Fallback: assume 3 levels up
	return filepath.Join(orchDir, "..", "..", "..")
}

// appModel wraps the ui.Model with watcher integration and state refresh logic.
type appModel struct {
	ui       ui.Model
	watcher  *watcher.Watcher
	executor *action.Executor
	orchDir  string
	wtBase   string
	planDir  string
}

func newAppModel(status *state.FullStatus, w *watcher.Watcher, exec *action.Executor, orchDir, wtBase, planDir string) *appModel {
	m := &appModel{
		ui:       ui.New(),
		watcher:  w,
		executor: exec,
		orchDir:  orchDir,
		wtBase:   wtBase,
		planDir:  planDir,
	}
	// Inject initial state into the UI.
	m.ui.Panes.Slices = fmt.Sprintf("Loaded %d slices", len(status.Slices))
	return m
}

func (m *appModel) Init() tea.Cmd {
	return m.watcher.Watch()
}

func (m *appModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg.(type) {
	case watcher.StateChangedMsg:
		// Re-read full state on any file change.
		if status, err := state.ReadFullStatus(m.orchDir, m.wtBase, m.planDir); err == nil {
			innerModel, cmd := m.ui.Update(ui.StateUpdatedMsg{Status: *status})
			m.ui = innerModel.(ui.Model)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}
		// Continue watching.
		cmds = append(cmds, m.watcher.Watch())
		return m, tea.Batch(cmds...)

	case watcher.LogLineMsg:
		// Forward log lines to the UI.
		wmsg := msg.(watcher.LogLineMsg)
		innerModel, cmd := m.ui.Update(ui.LogLineMsg{Line: wmsg.Line})
		m.ui = innerModel.(ui.Model)
		if cmd != nil {
			cmds = append(cmds, cmd)
		}
		cmds = append(cmds, m.watcher.Watch())
		return m, tea.Batch(cmds...)

	case watcher.WatcherErrorMsg:
		// Watcher stopped; don't re-subscribe.
		return m, nil
	}

	// Pass everything else to the inner UI model.
	innerModel, cmd := m.ui.Update(msg)
	m.ui = innerModel.(ui.Model)
	if cmd != nil {
		cmds = append(cmds, cmd)
	}

	// If the UI is quitting, don't send more commands.
	if m.ui.Quitting {
		return m, tea.Quit
	}

	return m, tea.Batch(cmds...)
}

func (m *appModel) View() string {
	return m.ui.View()
}
