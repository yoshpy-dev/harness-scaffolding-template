package cli

import (
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"

	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/scaffold"
)

// setupTestEmbedFS injects a minimal mock FS into scaffold.EmbeddedFS for testing.
func setupTestEmbedFS(t *testing.T) {
	t.Helper()
	scaffold.EmbeddedFS = fstest.MapFS{
		"templates/base/AGENTS.md":             {Data: []byte("# AGENTS\n")},
		"templates/base/CLAUDE.md":             {Data: []byte("# CLAUDE\n")},
		"templates/base/ralph.toml":            {Data: []byte("[pipeline]\nmodel = \"test\"\n")},
		"templates/base/.claude/settings.json": {Data: []byte("{}\n")},
		"templates/packs/golang/verify.sh":     {Data: []byte("#!/bin/sh\necho ok\n")},
		"templates/packs/golang/README.md":     {Data: []byte("# Go\n")},
		"templates/packs/typescript/verify.sh": {Data: []byte("#!/bin/sh\necho ok\n")},
		"templates/packs/typescript/README.md": {Data: []byte("# TS\n")},
	}
}

func TestExecuteInit_NewProject(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "0.1.0-test"

	dir := t.TempDir()
	target := filepath.Join(dir, "new-project")

	cfg := initConfig{
		ProjectName: "new-project",
		Packs:       []string{"golang"},
	}

	if err := executeInit(target, cfg, false); err != nil {
		t.Fatalf("executeInit: %v", err)
	}

	// Check files created.
	for _, f := range []string{"AGENTS.md", "CLAUDE.md", "ralph.toml", ".ralph/manifest.toml", "packs/languages/golang/verify.sh"} {
		if _, err := os.Stat(filepath.Join(target, f)); err != nil {
			t.Errorf("expected %s to exist: %v", f, err)
		}
	}

	// Check git init happened.
	if _, err := os.Stat(filepath.Join(target, ".git")); err != nil {
		t.Errorf("expected .git to exist: %v", err)
	}

	// Check manifest has files.
	m, err := scaffold.ReadManifest(filepath.Join(target, ".ralph", "manifest.toml"))
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	if _, ok := m.Files["AGENTS.md"]; !ok {
		t.Error("manifest missing AGENTS.md")
	}
	if m.Meta.Version != "0.1.0-test" {
		t.Errorf("manifest version = %q, want 0.1.0-test", m.Meta.Version)
	}
}

func TestExecuteInit_ExistingProject_DelegatesToUpgrade(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "0.1.0-test"

	dir := t.TempDir()

	// First init.
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("first init: %v", err)
	}

	// Add a user-owned file.
	userFile := filepath.Join(dir, "my-custom.md")
	if err := os.WriteFile(userFile, []byte("user content"), 0644); err != nil {
		t.Fatal(err)
	}

	// Re-init (should delegate to upgrade, preserving user files).
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("re-init: %v", err)
	}

	// User file should still exist.
	content, err := os.ReadFile(userFile)
	if err != nil {
		t.Fatalf("user file missing: %v", err)
	}
	if string(content) != "user content" {
		t.Errorf("user file content = %q, want %q", content, "user content")
	}
}

func TestExecuteInit_GitSkippedIfExists(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "0.1.0-test"

	dir := t.TempDir()
	// Pre-create .git directory.
	if err := os.MkdirAll(filepath.Join(dir, ".git"), 0755); err != nil {
		t.Fatal(err)
	}

	cfg := initConfig{ProjectName: "test", Packs: nil}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("executeInit: %v", err)
	}

	// .git should still exist (not re-initialized).
	if _, err := os.Stat(filepath.Join(dir, ".git")); err != nil {
		t.Error(".git should still exist")
	}
}

func TestRunUpgrade_AutoUpdate(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "0.2.0-test"

	dir := t.TempDir()

	// Create initial state with old version.
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	Version = "0.1.0-test"
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("init: %v", err)
	}

	// Bump version and run upgrade.
	Version = "0.2.0-test"
	if err := runUpgrade(dir, true); err != nil {
		t.Fatalf("upgrade: %v", err)
	}

	// Manifest should have new version.
	m, err := scaffold.ReadManifest(filepath.Join(dir, ".ralph", "manifest.toml"))
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	if m.Meta.Version != "0.2.0-test" {
		t.Errorf("manifest version = %q, want 0.2.0-test", m.Meta.Version)
	}
}

// Regression: upgrading across the same version twice must not drift the
// manifest into empty-hash entries or re-prompt the user for unchanged files.
func TestRunUpgrade_SameVersionIsIdempotent(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "1.0.0-test"

	dir := t.TempDir()
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("init: %v", err)
	}

	// Same-version upgrade twice.
	if err := runUpgrade(dir, false); err != nil {
		t.Fatalf("first upgrade: %v", err)
	}
	if err := runUpgrade(dir, false); err != nil {
		t.Fatalf("second upgrade: %v", err)
	}

	m, err := scaffold.ReadManifest(filepath.Join(dir, ".ralph", "manifest.toml"))
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	for k, v := range m.Files {
		if v.Hash == "" {
			t.Errorf("manifest entry %q has empty hash after upgrade", k)
		}
	}
	// Pack files must be tracked under the namespaced key exactly once.
	if _, ok := m.Files["packs/languages/golang/README.md"]; !ok {
		t.Error("manifest missing packs/languages/golang/README.md")
	}
	if _, ok := m.Files["README.md"]; ok {
		t.Error("manifest has unprefixed README.md (pack namespace leak)")
	}
}

// Heal path: if a manifest already contains empty-hash entries (bug state),
// a single same-version upgrade should repair them without prompting the
// user for files whose disk content matches the template.
func TestRunUpgrade_HealsCorruptedManifest(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "1.0.0-test"

	dir := t.TempDir()
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("init: %v", err)
	}

	// Corrupt the manifest: wipe all base-file hashes.
	manifestPath := filepath.Join(dir, ".ralph", "manifest.toml")
	m, err := scaffold.ReadManifest(manifestPath)
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	for k, v := range m.Files {
		if filepath.Base(k) == "AGENTS.md" || filepath.Base(k) == "CLAUDE.md" {
			v.Hash = ""
			m.Files[k] = v
		}
	}
	if err := m.Write(manifestPath); err != nil {
		t.Fatalf("Write manifest: %v", err)
	}

	// Upgrade without --force: since disk == template, heal must run without
	// prompting (stdin is a closed pipe inside tests).
	if err := runUpgrade(dir, false); err != nil {
		t.Fatalf("upgrade: %v", err)
	}

	m2, err := scaffold.ReadManifest(manifestPath)
	if err != nil {
		t.Fatalf("ReadManifest after heal: %v", err)
	}
	for _, name := range []string{"AGENTS.md", "CLAUDE.md"} {
		if m2.Files[name].Hash == "" {
			t.Errorf("%s still has empty hash after heal", name)
		}
	}
}

// Regression: if a pack diff fails (e.g. pack no longer available), the old
// manifest entries for that pack must be preserved, not silently dropped.
func TestRunUpgrade_PreservesOldPackEntriesOnDiffFailure(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "1.0.0-test"

	dir := t.TempDir()
	// Init with golang pack so its entries land in the manifest.
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("init: %v", err)
	}

	// Simulate a pack that used to be installed but whose FS no longer loads.
	// We inject the pack name into Meta.Packs and remove the pack's template
	// files from the embedded FS, so scaffold.PackFS will fail for it while
	// golang still diffs normally.
	manifestPath := filepath.Join(dir, ".ralph", "manifest.toml")
	m, err := scaffold.ReadManifest(manifestPath)
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	m.Meta.Packs = []string{"golang", "ghostpack"}
	// Seed a manifest entry for the missing pack so we can detect preservation.
	m.SetFile("packs/languages/ghostpack/verify.sh", "sha256:deadbeef")
	if err := m.Write(manifestPath); err != nil {
		t.Fatalf("Write manifest: %v", err)
	}

	// Run upgrade — ghostpack will fail to load but golang should succeed.
	if err := runUpgrade(dir, false); err != nil {
		t.Fatalf("upgrade: %v", err)
	}

	m2, err := scaffold.ReadManifest(manifestPath)
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	if _, ok := m2.Files["packs/languages/ghostpack/verify.sh"]; !ok {
		t.Error("ghostpack entry was dropped after diff failure — expected preservation")
	}
	if _, ok := m2.Files["packs/languages/golang/README.md"]; !ok {
		t.Error("golang entry was dropped after ghostpack failure")
	}
}

func TestRunDoctor_Passes(t *testing.T) {
	setupTestEmbedFS(t)
	Version = "0.1.0-test"

	dir := t.TempDir()

	// Init a project first.
	cfg := initConfig{ProjectName: "test", Packs: []string{"golang"}}
	if err := executeInit(dir, cfg, false); err != nil {
		t.Fatalf("init: %v", err)
	}

	// Doctor should not error fatally (it may warn about missing claude CLI).
	// We just verify it doesn't panic.
	_ = runDoctor(dir)
}

func TestNewRootCmd_HasAllSubcommands(t *testing.T) {
	root := NewRootCmd()
	expected := []string{"init", "upgrade", "run", "retry", "abort", "doctor", "pack", "version", "status"}
	for _, name := range expected {
		found := false
		for _, cmd := range root.Commands() {
			if cmd.Name() == name {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("missing subcommand: %s", name)
		}
	}
}
