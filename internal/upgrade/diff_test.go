package upgrade

import (
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"

	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/scaffold"
)

func setupTestProject(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()

	// Create a file on disk.
	if err := os.WriteFile(filepath.Join(dir, "file.md"), []byte("original"), 0644); err != nil {
		t.Fatal(err)
	}

	// Create manifest.
	m := scaffold.NewManifest("0.1.0")
	m.SetFile("file.md", scaffold.HashBytes([]byte("original")))

	manifestDir := filepath.Join(dir, ".ralph")
	if err := os.MkdirAll(manifestDir, 0755); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(manifestDir, "manifest.toml")
	if err := m.Write(manifestPath); err != nil {
		t.Fatal(err)
	}

	return dir, manifestPath
}

func TestComputeDiffs_AutoUpdate(t *testing.T) {
	dir, manifestPath := setupTestProject(t)

	// New template with updated content.
	newFS := fstest.MapFS{
		"file.md": {Data: []byte("updated")},
	}

	diffs, err := ComputeDiffs(manifestPath, dir, newFS)
	if err != nil {
		t.Fatal(err)
	}

	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionAutoUpdate {
		t.Errorf("action = %d, want ActionAutoUpdate (%d)", diffs[0].Action, ActionAutoUpdate)
	}
}

func TestComputeDiffs_Conflict(t *testing.T) {
	dir, manifestPath := setupTestProject(t)

	// User edits the file.
	if err := os.WriteFile(filepath.Join(dir, "file.md"), []byte("user edit"), 0644); err != nil {
		t.Fatal(err)
	}

	// New template also changes.
	newFS := fstest.MapFS{
		"file.md": {Data: []byte("updated")},
	}

	diffs, err := ComputeDiffs(manifestPath, dir, newFS)
	if err != nil {
		t.Fatal(err)
	}

	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionConflict {
		t.Errorf("action = %d, want ActionConflict (%d)", diffs[0].Action, ActionConflict)
	}
}

func TestComputeDiffs_AddNewFile(t *testing.T) {
	dir, manifestPath := setupTestProject(t)

	newFS := fstest.MapFS{
		"file.md":     {Data: []byte("original")},
		"new-file.md": {Data: []byte("new content")},
	}

	diffs, err := ComputeDiffs(manifestPath, dir, newFS)
	if err != nil {
		t.Fatal(err)
	}

	var addCount int
	for _, d := range diffs {
		if d.Action == ActionAdd {
			addCount++
		}
	}
	if addCount != 1 {
		t.Errorf("add count = %d, want 1", addCount)
	}
}

func TestComputeDiffs_RemoveFile(t *testing.T) {
	dir, manifestPath := setupTestProject(t)

	// New template doesn't have file.md anymore.
	newFS := fstest.MapFS{
		"other.md": {Data: []byte("other")},
	}

	diffs, err := ComputeDiffs(manifestPath, dir, newFS)
	if err != nil {
		t.Fatal(err)
	}

	var removeCount int
	for _, d := range diffs {
		if d.Action == ActionRemove {
			removeCount++
		}
	}
	if removeCount != 1 {
		t.Errorf("remove count = %d, want 1", removeCount)
	}
}
