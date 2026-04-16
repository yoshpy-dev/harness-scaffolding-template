package cli

import (
	"fmt"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/scaffold"
)

func newPackCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "pack",
		Short: "Manage language packs",
	}

	cmd.AddCommand(newPackAddCmd())
	cmd.AddCommand(newPackListCmd())

	return cmd
}

func newPackAddCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "add <language>",
		Short: "Add a language pack to the project",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return addPack(".", args[0])
		},
	}
}

func newPackListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List available language packs",
		RunE: func(cmd *cobra.Command, args []string) error {
			packs, err := scaffold.AvailablePacks()
			if err != nil {
				return err
			}
			fmt.Println("Available language packs:")
			for _, p := range packs {
				fmt.Printf("  - %s\n", p)
			}
			return nil
		},
	}
}

func addPack(targetDir string, lang string) error {
	absDir, err := filepath.Abs(targetDir)
	if err != nil {
		return err
	}

	packFS, err := scaffold.PackFS(lang)
	if err != nil {
		return fmt.Errorf("language pack %q not found", lang)
	}

	result, hashes, err := scaffold.RenderFS(packFS, scaffold.RenderOptions{
		TargetDir: absDir,
		Overwrite: true,
	})
	if err != nil {
		return fmt.Errorf("rendering pack %s: %w", lang, err)
	}

	// Update manifest.
	manifestPath := filepath.Join(absDir, ".ralph", "manifest.toml")
	manifest, err := scaffold.ReadManifest(manifestPath)
	if err != nil {
		fmt.Printf("⚠ Could not update manifest: %v\n", err)
	} else {
		for path, hash := range hashes {
			manifest.SetFile(path, hash)
		}
		if err := manifest.Write(manifestPath); err != nil {
			fmt.Printf("⚠ Could not write manifest: %v\n", err)
		}
	}

	created := len(result.Created)
	updated := len(result.Overwritten)
	fmt.Printf("✓ Pack %s added (%d created, %d updated)\n", lang, created, updated)

	return nil
}
