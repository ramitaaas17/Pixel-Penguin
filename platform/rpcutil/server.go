package rpcutil

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"math"
	"strings"
	"unicode/utf8"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

func InstanceHeader(instanceName string) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, request any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if err := grpc.SetHeader(ctx, metadata.Pairs("x-instance-name", instanceName)); err != nil {
			return nil, status.Error(codes.Internal, "No se pudo preparar la respuesta")
		}
		log.Printf("instance=%s rpc=%s", instanceName, info.FullMethod)
		return handler(ctx, request)
	}
}

func DatabaseError(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return status.Error(codes.NotFound, "Registro no encontrado")
	}
	if errors.Is(err, context.Canceled) {
		return status.Error(codes.Canceled, "Solicitud cancelada")
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return status.Error(codes.DeadlineExceeded, "Se agotó el tiempo de la solicitud")
	}
	log.Printf("database operation failed: %v", err)
	return status.Error(codes.Internal, "No se pudo completar la operación")
}

func ValidID(id int64) bool        { return id > 0 && id <= math.MaxInt32 }
func ValidAmount(value int64) bool { return value >= 0 && value <= math.MaxInt32 }
func ValidName(value string) bool {
	return strings.TrimSpace(value) != "" && utf8.RuneCountInString(value) <= 100
}

type databaseHealth struct {
	healthpb.UnimplementedHealthServer
	db *sql.DB
}

func RegisterHealth(server *grpc.Server, db *sql.DB) {
	healthpb.RegisterHealthServer(server, &databaseHealth{db: db})
}

func (health *databaseHealth) Check(ctx context.Context, request *healthpb.HealthCheckRequest) (*healthpb.HealthCheckResponse, error) {
	state := healthpb.HealthCheckResponse_SERVING
	if err := health.db.PingContext(ctx); err != nil {
		state = healthpb.HealthCheckResponse_NOT_SERVING
	}
	return &healthpb.HealthCheckResponse{Status: state}, nil
}
