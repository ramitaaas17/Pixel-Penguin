package rpc

import (
	"cafeteria/models"
	"context"
	"encoding/base64"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"testing"
)

type orderStore struct {
	OrderStore
	owner int64
}

func (store *orderStore) ObtenerTodos(ctx context.Context, owner int64) ([]models.Pedido, error) {
	store.owner = owner
	return nil, nil
}
func (store *orderStore) ObtenerPorId(ctx context.Context, id int) (*models.Pedido, error) {
	return &models.Pedido{Id: id, JugadorId: 9}, nil
}

type sessionLookup struct{}

func (lookup *sessionLookup) GetSession(ctx context.Context, request *pb.Empty, options ...grpc.CallOption) (*pb.Session, error) {
	return &pb.Session{Player: &pb.Player{Id: 7}}, nil
}
func TestOrdersRequireSessionAndCannotImpersonate(t *testing.T) {
	store := &orderStore{}
	server := New(store, &sessionLookup{})
	if _, err := server.CreateOrder(context.Background(), &pb.CreateOrderRequest{PlayerId: 7}); status.Code(err) != codes.Unauthenticated {
		t.Fatal(err)
	}
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs("authorization", "Bearer "+token))
	if _, err := server.ListOrders(ctx, &pb.Empty{}); err != nil || store.owner != 7 {
		t.Fatalf("owner=%d error=%v", store.owner, err)
	}
	if _, err := server.GetOrder(ctx, &pb.IdRequest{Id: 5}); status.Code(err) != codes.NotFound {
		t.Fatal("another owner's order leaked", err)
	}
	if _, err := server.CreateOrder(ctx, &pb.CreateOrderRequest{PlayerId: 9, Quantity: 1}); status.Code(err) != codes.FailedPrecondition {
		t.Fatal("legacy purchase was accepted", err)
	}
}
