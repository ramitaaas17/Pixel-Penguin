package rpc

import (
	"context"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"jugadores/models"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
)

type PlayerStore interface {
	ObtenerTodos(context.Context) ([]models.Jugador, error)
	ObtenerPorId(context.Context, int) (*models.Jugador, error)
	Crear(context.Context, string, int) (*models.Jugador, error)
	ActualizarMonedas(context.Context, int, int) (*models.Jugador, error)
}

type Server struct {
	pb.UnimplementedPlayersServer
	store    PlayerStore
	sessions SessionLookup
	Coffee   CoffeeGames
}

type SessionLookup interface {
	GetSession(context.Context, *pb.Empty) (*pb.Session, error)
}

func New(store PlayerStore, sessions SessionLookup) *Server {
	return &Server{store: store, sessions: sessions}
}
func player(record *models.Jugador) *pb.Player {
	return &pb.Player{Id: int64(record.Id), Name: record.Nombre, Coins: int64(record.Monedas)}
}

func (server *Server) ListPlayers(ctx context.Context, request *pb.Empty) (*pb.PlayerList, error) {
	if _, err := server.sessions.GetSession(ctx, &pb.Empty{}); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.PermissionDenied, "La lista de jugadores es privada")
}
func (server *Server) GetPlayer(ctx context.Context, request *pb.IdRequest) (*pb.Player, error) {
	if !rpcutil.ValidID(request.Id) {
		return nil, status.Error(codes.InvalidArgument, "ID inválido")
	}
	identity, err := server.sessions.GetSession(ctx, &pb.Empty{})
	if err != nil {
		return nil, err
	}
	if request.Id != identity.Player.Id {
		return nil, status.Error(codes.PermissionDenied, "Solo puedes consultar tu propio jugador")
	}
	record, err := server.store.ObtenerPorId(ctx, int(request.Id))
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	return player(record), nil
}
func (server *Server) CreatePlayer(ctx context.Context, request *pb.CreatePlayerRequest) (*pb.Player, error) {
	if _, err := server.sessions.GetSession(ctx, &pb.Empty{}); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.PermissionDenied, "Los jugadores se crean al registrar una cuenta")
}
func (server *Server) UpdateCoins(ctx context.Context, request *pb.UpdateCoinsRequest) (*pb.Player, error) {
	if _, err := server.sessions.GetSession(ctx, &pb.Empty{}); err != nil {
		return nil, err
	}
	return nil, status.Error(codes.PermissionDenied, "Las monedas solo pueden cambiar mediante operaciones del servidor")
}
