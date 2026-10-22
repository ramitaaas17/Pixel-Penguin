package rpc

import (
	"context"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
	"pixelpenguin/platform/session"
	"tienda/models"
)

type ProductStore interface {
	ObtenerTodos(context.Context) ([]models.Producto, error)
	ObtenerPorId(context.Context, int) (*models.Producto, error)
	Crear(context.Context, string, float64, int) (*models.Producto, error)
	ActualizarStock(context.Context, int, int) (*models.Producto, error)
}

type Server struct {
	pb.UnimplementedStoreServer
	store    ProductStore
	sessions session.Validator
}

func New(store ProductStore, sessions session.Validator) *Server {
	return &Server{store: store, sessions: sessions}
}
func product(record *models.Producto) *pb.Product {
	return &pb.Product{Id: int64(record.Id), Name: record.Nombre, Price: record.Precio, Stock: int64(record.Stock)}
}

func (server *Server) ListProducts(ctx context.Context, request *pb.Empty) (*pb.ProductList, error) {
	records, err := server.store.ObtenerTodos(ctx)
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	result := &pb.ProductList{}
	for i := range records {
		result.Products = append(result.Products, product(&records[i]))
	}
	return result, nil
}
func (server *Server) GetProduct(ctx context.Context, request *pb.IdRequest) (*pb.Product, error) {
	if !rpcutil.ValidID(request.Id) {
		return nil, status.Error(codes.InvalidArgument, "ID inválido")
	}
	record, err := server.store.ObtenerPorId(ctx, int(request.Id))
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	return product(record), nil
}
func (server *Server) CreateProduct(ctx context.Context, request *pb.CreateProductRequest) (*pb.Product, error) {
	if _, err := session.Require(ctx, server.sessions); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.PermissionDenied, "El catálogo se gestiona desde el servidor")
}
func (server *Server) UpdateStock(ctx context.Context, request *pb.UpdateStockRequest) (*pb.Product, error) {
	if _, err := session.Require(ctx, server.sessions); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.PermissionDenied, "Las existencias solo cambian mediante compras confirmadas")
}
