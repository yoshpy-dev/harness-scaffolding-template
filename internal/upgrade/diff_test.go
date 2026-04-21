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

// Regression: ActionSkip must carry NewHash so callers can rewrite the
// manifest with a real hash instead of an empty string.
func TestComputeDiffs_Skip_PreservesHash(t *testing.T) {
	dir, manifestPath := setupTestProject(t)

	// Same content in newFS → template unchanged → ActionSkip.
	content := []byte("original")
	newFS := fstest.MapFS{
		"file.md": {Data: content},
	}

	diffs, err := ComputeDiffs(manifestPath, dir, newFS)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionSkip {
		t.Fatalf("action = %d, want ActionSkip", diffs[0].Action)
	}
	want := scaffold.HashBytes(content)
	if diffs[0].NewHash != want {
		t.Errorf("NewHash = %q, want %q", diffs[0].NewHash, want)
	}
}

// Regression: a pack-scoped manifest subset (keys stripped of the pack prefix)
// should resolve pack FS paths as ActionSkip when disk + template match,
// not mis-classify them as ActionAdd.
func TestComputeDiffsWithManifest_PackPrefixedSubset(t *testing.T) {
	dir := t.TempDir()

	// Simulate pack files rendered to disk under packs/languages/golang/.
	packDir := filepath.Join(dir, "packs", "languages", "golang")
	if err := os.MkdirAll(packDir, 0755); err != nil {
		t.Fatal(err)
	}
	readme := []byte("pack readme")
	if err := os.WriteFile(filepath.Join(packDir, "README.md"), readme, 0644); err != nil {
		t.Fatal(err)
	}

	// Full manifest keys are namespaced under packs/languages/golang/,
	// but we pass a scoped subset with the prefix stripped.
	packManifest := scaffold.NewManifest("0.1.0")
	packManifest.SetFile("README.md", scaffold.HashBytes(readme))

	packFS := fstest.MapFS{
		"README.md": {Data: readme},
	}

	diffs, err := ComputeDiffsWithManifest(packManifest, packDir, packFS, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionSkip {
		t.Fatalf("action = %d, want ActionSkip (got Add=%d)", diffs[0].Action, ActionAdd)
	}
}

// Regression: an empty-hash manifest entry (caused by the prior bug) should
// self-heal when the on-disk content matches the template — no conflict, no
// user prompt, just a hash repair via ActionSkip.
func TestComputeDiffs_HealsEmptyHash_WhenDiskMatchesTemplate(t *testing.T) {
	dir := t.TempDir()
	content := []byte("pristine")
	if err := os.WriteFile(filepath.Join(dir, "file.md"), content, 0644); err != nil {
		t.Fatal(err)
	}

	// Simulate corrupted manifest (hash = "").
	m := scaffold.NewManifest("0.1.0")
	m.SetFile("file.md", "")

	newFS := fstest.MapFS{
		"file.md": {Data: content},
	}

	diffs, err := ComputeDiffsWithManifest(m, dir, newFS, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionSkip {
		t.Errorf("action = %d, want ActionSkip", diffs[0].Action)
	}
	if diffs[0].NewHash == "" {
		t.Errorf("NewHash should be populated for heal")
	}
}

// Empty-hash entries where disk differs from template must still surface as
// conflicts so the user is asked instead of silently overwriting edits.
// Additionally, the conflict must carry OldHash=newHash so that a non-
// interactive "skip" resolution rewrites the manifest with a real hash
// and ends the perpetual-conflict loop.
func TestComputeDiffs_EmptyHashConflictsWhenDiskDiffers(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "file.md"), []byte("user edit"), 0644); err != nil {
		t.Fatal(err)
	}
	m := scaffold.NewManifest("0.1.0")
	m.SetFile("file.md", "")

	template := []byte("template")
	newFS := fstest.MapFS{
		"file.md": {Data: template},
	}

	diffs, err := ComputeDiffsWithManifest(m, dir, newFS, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionConflict {
		t.Fatalf("action = %d, want ActionConflict", diffs[0].Action)
	}
	wantHash := scaffold.HashBytes(template)
	if diffs[0].OldHash != wantHash {
		t.Errorf("OldHash = %q, want newHash %q (heal contract)", diffs[0].OldHash, wantHash)
	}
}

// Regression: a file absent from the manifest but present on disk with
// content that differs from the template must surface as ActionConflict,
// not ActionAdd. Prior behavior would silently overwrite the user's file
// when a later template release reintroduced a previously-removed path.
func TestComputeDiffs_AddBecomesConflictWhenDiskDiffers(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "returning.md"), []byte("user kept this"), 0644); err != nil {
		t.Fatal(err)
	}
	m := scaffold.NewManifest("0.1.0") // no entry for returning.md

	newFS := fstest.MapFS{
		"returning.md": {Data: []byte("new template version")},
	}

	diffs, err := ComputeDiffsWithManifest(m, dir, newFS, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 {
		t.Fatalf("diffs = %d, want 1", len(diffs))
	}
	if diffs[0].Action != ActionConflict {
		t.Fatalf("action = %d, want ActionConflict (reintroduction safeguard)", diffs[0].Action)
	}
}

// Ada: if the disk file already matches the new template, ActionAdd is safe
// (no conflict prompt needed). This covers the no-op re-add case.
func TestComputeDiffs_AddStaysAddWhenDiskMatchesTemplate(t *testing.T) {
	dir := t.TempDir()
	content := []byte("identical")
	if err := os.WriteFile(filepath.Join(dir, "same.md"), content, 0644); err != nil {
		t.Fatal(err)
	}
	m := scaffold.NewManifest("0.1.0")

	newFS := fstest.MapFS{
		"same.md": {Data: content},
	}

	diffs, err := ComputeDiffsWithManifest(m, dir, newFS, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(diffs) != 1 || diffs[0].Action != ActionAdd {
		t.Fatalf("action = %v, want ActionAdd", diffs)
	}
}
