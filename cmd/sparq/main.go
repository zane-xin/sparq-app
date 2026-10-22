package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/zane-xin/sparq"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	err := sparq.ExecuteWithOptions(ctx, sparq.CommandOptions{Name: "sparq"}, os.Args[1:]...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sparq command failed: %v\n", err)
		os.Exit(1)
	}
}
