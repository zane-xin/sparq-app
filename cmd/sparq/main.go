package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/zane-xin/sparq"
	"github.com/zane-xin/sparq/modules"
	"github.com/zane-xin/sparq/modules/organization"
	"github.com/zane-xin/sparq/modules/site"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	err := sparq.ExecuteWithOptions(ctx, sparq.CommandOptions{
		Name:   "sparq",
		Config: sparq.Config{Modules: []modules.Definition{site.Definition(), organization.Definition()}},
	}, os.Args[1:]...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sparq command failed: %v\n", err)
		os.Exit(1)
	}
}
