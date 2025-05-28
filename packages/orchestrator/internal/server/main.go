package server

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"net"
	"os"
	"sync"

	"github.com/e2b-dev/infra/packages/shared/pkg/env"
	grpc_logging "github.com/grpc-ecosystem/go-grpc-middleware/logging"

	grpc_zap "github.com/grpc-ecosystem/go-grpc-middleware/logging/zap"
	"github.com/grpc-ecosystem/go-grpc-middleware/v2/interceptors/recovery"
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/health/grpc_health_v1"

	"github.com/e2b-dev/infra/packages/orchestrator/internal/dns"
	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox"
	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox/network"
	"github.com/e2b-dev/infra/packages/orchestrator/internal/sandbox/template"
	e2bgrpc "github.com/e2b-dev/infra/packages/shared/pkg/grpc"
	"github.com/e2b-dev/infra/packages/shared/pkg/grpc/orchestrator"
	e2blogging "github.com/e2b-dev/infra/packages/shared/pkg/logging"
	"github.com/e2b-dev/infra/packages/shared/pkg/smap"
)

const ServiceName = "orchestrator"

type server struct {
	orchestrator.UnimplementedSandboxServiceServer
	sandboxes     *smap.Map[*sandbox.Sandbox]
	dns           *dns.DNS
	tracer        trace.Tracer
	networkPool   *network.Pool
	templateCache *template.Cache

	pauseMu sync.Mutex
}

type Service struct {
	server   *server
	grpc     *grpc.Server
	dns      *dns.DNS
	port     uint16
	shutdown struct {
		once sync.Once
		op   func(context.Context) error
		err  error
	}
}

func New(ctx context.Context, port uint) (*Service, error) {
	if port > math.MaxUint16 {
		return nil, fmt.Errorf("%d is larger than maximum possible port %d", port, math.MaxInt16)
	}
	log.Printf("port finish")
	srv := &Service{port: uint16(port)}
	log.Printf("Service finish")

	log.Printf("Using GCS as storage provider")
	if os.Getenv("TEMPLATE_BUCKET_NAME") == "" {
		log.Printf("Warning: TEMPLATE_BUCKET_NAME environment variable is not set")
	} else {
		log.Printf("GCS configuration verified - using bucket: %s",
			os.Getenv("TEMPLATE_BUCKET_NAME"))
	}

	templateCache, err := template.NewCache(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create template cache: %w", err)
	}
	log.Printf("templateCache finish")

	networkPool, err := network.NewPool(ctx, network.NewSlotsPoolSize, network.ReusedSlotsPoolSize)
	if err != nil {
		return nil, fmt.Errorf("failed to create network pool: %w", err)
	}

	log.Printf("networkPool finish")

	loggerSugar, err := e2blogging.New(env.IsLocal())
	if err != nil {
		return nil, fmt.Errorf("initializing logger: %w", err)
	}

	log.Printf("loggerSugar finish")

	logger := loggerSugar.Desugar()

	// BLOCK: initialize services
	{
		log.Printf("into dns")
		srv.dns = dns.New()

		opts := []grpc_zap.Option{e2blogging.WithoutHealthCheck()}

		srv.grpc = grpc.NewServer(
			grpc.StatsHandler(e2bgrpc.NewStatsWrapper(otelgrpc.NewServerHandler())),
			grpc.ChainUnaryInterceptor(
				recovery.UnaryServerInterceptor(),
				grpc_zap.UnaryServerInterceptor(logger, opts...),
				grpc_zap.PayloadUnaryServerInterceptor(logger, withoutHealthCheckPayload()),
			),
			grpc.ChainStreamInterceptor(
				grpc_zap.StreamServerInterceptor(logger, opts...),
				grpc_zap.PayloadStreamServerInterceptor(logger, withoutHealthCheckPayload()),
			),
		)
		log.Printf("grpc finish")

		srv.server = &server{
			tracer:        otel.Tracer(ServiceName),
			dns:           srv.dns,
			sandboxes:     smap.New[*sandbox.Sandbox](),
			networkPool:   networkPool,
			templateCache: templateCache,
		}

		log.Printf("srv.server finish")
	}

	orchestrator.RegisterSandboxServiceServer(srv.grpc, srv.server)
	log.Printf("orchestrator.RegisterSandboxServiceServer finish")
	grpc_health_v1.RegisterHealthServer(srv.grpc, health.NewServer())
	log.Printf("grpc_health_v1 finish")

	return srv, nil
}

// Start launches
func (srv *Service) Start(context.Context) error {
	if srv.server == nil || srv.dns == nil || srv.grpc == nil {
		return errors.New("orchestrator services are not initialized")
	}

	go func() {
		log.Printf("Starting DNS server")
		if err := srv.dns.Start("127.0.0.4", 53); err != nil {
			log.Panic(fmt.Errorf("Failed running DNS server: %w", err))
		}
	}()

	// the listener is closed by the shutdown operation
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", srv.port))
	if err != nil {
		return fmt.Errorf("failed to listen on port %d: %w", srv.port, err)
	}

	log.Printf("starting server on port %d", srv.port)

	go func() {
		if err := srv.grpc.Serve(lis); err != nil {
			log.Panic(fmt.Errorf("failed to serve: %w", err))
		}
	}()

	srv.shutdown.op = func(ctx context.Context) error {
		var errs []error

		srv.grpc.GracefulStop()

		if err := lis.Close(); err != nil {
			errs = append(errs, err)
		}

		if err := srv.dns.Close(ctx); err != nil {
			errs = append(errs, err)
		}

		return errors.Join(errs...)
	}

	return nil
}

func (srv *Service) Close(ctx context.Context) error {
	srv.shutdown.once.Do(func() {
		if srv.shutdown.op == nil {
			// should only be true if there was an error
			// during startup.
			return
		}

		srv.shutdown.err = srv.shutdown.op(ctx)
		srv.shutdown.op = nil
	})
	return srv.shutdown.err
}

func withoutHealthCheckPayload() grpc_logging.ServerPayloadLoggingDecider {
	return func(ctx context.Context, fullMethodName string, servingObject interface{}) bool {
		// will not log gRPC calls if it was a call to healthcheck and no error was raised
		if fullMethodName == "/grpc.health.v1.Health/Check" {
			return false
		}

		// by default everything will be logged
		return true
	}
}
