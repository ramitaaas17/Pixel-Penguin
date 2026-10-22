package session

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"strings"
)

type Validator interface {
	GetSession(context.Context, *pb.Empty, ...grpc.CallOption) (*pb.Session, error)
}

func Token(ctx context.Context) (string, error) {
	values := metadata.ValueFromIncomingContext(ctx, "authorization")
	if len(values) != 1 {
		return "", status.Error(codes.Unauthenticated, "Inicia sesión para continuar")
	}
	fields := strings.Fields(values[0])
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
		return "", status.Error(codes.Unauthenticated, "Sesión inválida")
	}
	if _, err := Hash(fields[1]); err != nil {
		return "", err
	}
	return fields[1], nil
}
func Hash(token string) ([]byte, error) {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(raw) != 32 || len(token) != 43 {
		return nil, status.Error(codes.Unauthenticated, "Sesión inválida")
	}
	hash := sha256.Sum256([]byte(token))
	return hash[:], nil
}
func Require(ctx context.Context, validator Validator) (*pb.Session, error) {
	token, err := Token(ctx)
	if err != nil {
		return nil, err
	}
	outgoing := metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+token)
	return validator.GetSession(outgoing, &pb.Empty{})
}
