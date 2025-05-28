package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/server"
	"github.com/e2b-dev/infra/packages/shared/pkg/env"
	"github.com/e2b-dev/infra/packages/shared/pkg/telemetry"
)

const defaultPort = 5008

var commitSHA string

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sig, sigCancel := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer sigCancel()

	var port uint

	flag.UintVar(&port, "port", defaultPort, "orchestrator server port")
	flag.Parse()

	wg := &sync.WaitGroup{}
	exitCode := &atomic.Int32{}
	telemetrySignal := make(chan struct{})

	// defer waiting on the waitgroup so that this runs even when
	// there's a panic.
	defer wg.Wait()

	if !env.IsLocal() {
		shutdown := telemetry.InitOTLPExporter(ctx, server.ServiceName, "no")
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-telemetrySignal
			if err := shutdown(ctx); err != nil {
				log.Printf("telemetry shutdown: %v", err)
				exitCode.Add(1)
			}
		}()
	}

	log.Println("Starting orchestrator", "commit", commitSHA)

	// Check if AWS is enabled and setup AWS configuration
	if os.Getenv("AWS_ENABLED") == "true" {
		log.Println("AWS is enabled, setting up AWS configuration")

		// AWS region must be set for the AWS SDK to work correctly
		if os.Getenv("AWS_REGION") == "" {
			log.Println("AWS_REGION is not set, defaulting to us-east-1")
			os.Setenv("AWS_REGION", "us-east-1")
		}

		// Verify S3 bucket name is set
		if os.Getenv("TEMPLATE_AWS_BUCKET_NAME") == "" {
			log.Fatalf("TEMPLATE_AWS_BUCKET_NAME must be set when AWS is enabled")
		}

		// Check AWS credentials (but don't fail if they're not set, as they might be provided through IAM roles)
		if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
			log.Println("AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set. If not using IAM roles, authentication may fail.")
		}

		// Check if using temporary credentials
		if os.Getenv("AWS_SESSION_TOKEN") != "" {
			log.Println("Using temporary AWS credentials with session token")
		}

		log.Printf("AWS configuration: Region=%s, Bucket=%s",
			os.Getenv("AWS_REGION"),
			os.Getenv("TEMPLATE_AWS_BUCKET_NAME"))
	}

	srv, err := server.New(ctx, port)
	if err != nil {
		log.Fatalf("failed to create server: %v", err)
	}

	log.Println("Finised new server...")

	wg.Add(1)
	go func() {
		defer wg.Done()
		var err error

		defer func() {
			// recover the panic because the service manages a number of go routines
			// that can panic, so catching this here allows for the rest of the process
			// to terminate in a more orderly manner.
			if perr := recover(); perr != nil {
				// many of the panics use log.Panicf which means we're going to log
				// some panic messages twice, but this seems ok, and temporary while
				// we clean up logging.
				log.Printf("caught panic in service: %v", perr)
				exitCode.Add(1)
				err = errors.Join(err, fmt.Errorf("server panic: %v", perr))
			}

			// if we encountered an err, but the signal context was NOT canceled, then
			// the outer context needs to be canceled so the remainder of the service
			// can shutdown.
			if err != nil && sig.Err() == nil {
				log.Printf("service ended early without signal")
				cancel()
			}
		}()

		// this sets the error declared above so the function
		// in the defer can check it.
		if err = srv.Start(ctx); err != nil {
			log.Printf("orchestrator service: %v", err)
			exitCode.Add(1)
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		defer close(telemetrySignal)
		<-sig.Done()
		if err := srv.Close(ctx); err != nil {
			log.Printf("grpc service: %v", err)
			exitCode.Add(1)
		}
	}()

	wg.Wait()

	os.Exit(int(exitCode.Load()))
}
