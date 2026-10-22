package rpc

import (
	"cafeteria/models"
	"context"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
	"pixelpenguin/platform/session"
)

type OrderStore interface {
	ObtenerTodos(context.Context, int64) ([]models.Pedido, error)
	ObtenerPorId(context.Context, int) (*models.Pedido, error)
}
type Server struct {
	pb.UnimplementedCafeteriaServer
	store    OrderStore
	sessions session.Validator
}

func New(store OrderStore, sessions session.Validator) *Server {
	return &Server{store: store, sessions: sessions}
}
func order(record *models.Pedido) *pb.Order {
	return &pb.Order{Id: int64(record.Id), Product: record.Producto, Quantity: int32(record.Cantidad), Status: record.Estado, PlayerId: record.JugadorId}
}
func (server *Server) ListOrders(ctx context.Context, request *pb.Empty) (*pb.OrderList, error) {
	identity, err := session.Require(ctx, server.sessions)
	if err != nil {
		return nil, err
	}
	records, err := server.store.ObtenerTodos(ctx, identity.Player.Id)
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	result := &pb.OrderList{}
	for i := range records {
		result.Orders = append(result.Orders, order(&records[i]))
	}
	return result, nil
}
func (server *Server) GetOrder(ctx context.Context, request *pb.IdRequest) (*pb.Order, error) {
	identity, err := session.Require(ctx, server.sessions)
	if err != nil {
		return nil, err
	}
	if !rpcutil.ValidID(request.Id) {
		return nil, status.Error(codes.InvalidArgument, "ID inválido")
	}
	record, err := server.store.ObtenerPorId(ctx, int(request.Id))
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	if record.JugadorId != identity.Player.Id {
		return nil, status.Error(codes.NotFound, "Registro no encontrado")
	}
	return order(record), nil
}
func (server *Server) CreateOrder(ctx context.Context, request *pb.CreateOrderRequest) (*pb.Order, error) {
	if _, err := session.Require(ctx, server.sessions); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.FailedPrecondition, "Las compras estarán disponibles al completar su validación en el servidor")
}
