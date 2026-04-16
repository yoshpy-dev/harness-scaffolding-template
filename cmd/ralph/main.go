package main

import (
	"fmt"
	"os"

	"github.com/yoshpy-dev/harness-engineering-scaffolding-template/internal/cli"
)

func main() {
	// Inject build-time variables.
	cli.Version = Version
	cli.GitCommit = GitCommit
	cli.BuildDate = BuildDate

	if err := cli.NewRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
