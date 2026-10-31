package rpc

import (
	"context"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"pixelpenguin/platform/coffeegame"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

type CoffeeGames interface {
	Start(context.Context, int64) (coffeegame.Plan, error)
	Finish(context.Context, int64, string, []coffeegame.Action) (coffeegame.Result, error)
}

func (s *Server) StartCoffeeGame(ctx context.Context, _ *pb.Empty) (*pb.CoffeePlan, error) {
	identity, err := s.sessions.GetSession(ctx, &pb.Empty{})
	if err != nil {
		return nil, err
	}
	if s.Coffee == nil {
		return nil, status.Error(codes.Unavailable, "Minijuego no disponible")
	}
	plan, err := s.Coffee.Start(ctx, identity.Player.Id)
	if err != nil {
		return nil, err
	}
	result := &pb.CoffeePlan{RunId: plan.ID, DurationMs: int32(plan.Duration)}
	for _, recipe := range plan.Recipes {
		result.Recipes = append(result.Recipes, int32(recipe))
	}
	for _, drop := range plan.Drops {
		result.Drops = append(result.Drops, &pb.CoffeeDrop{Id: int32(drop.ID), Kind: int32(drop.Kind), AtMs: int32(drop.At), UntilMs: int32(drop.Until)})
	}
	return result, nil
}
func (s *Server) FinishCoffeeGame(ctx context.Context, request *pb.FinishCoffeeRequest) (*pb.CoffeeResult, error) {
	identity, err := s.sessions.GetSession(ctx, &pb.Empty{})
	if err != nil {
		return nil, err
	}
	if s.Coffee == nil {
		return nil, status.Error(codes.Unavailable, "Minijuego no disponible")
	}
	if len(request.Actions) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Demasiadas acciones")
	}
	actions := make([]coffeegame.Action, 0, len(request.Actions))
	for _, action := range request.Actions {
		actions = append(actions, coffeegame.Action{ID: int(action.DropId), At: int(action.AtMs)})
	}
	result, err := s.Coffee.Finish(ctx, identity.Player.Id, request.RunId, actions)
	if err != nil {
		return nil, err
	}
	return &pb.CoffeeResult{Score: int64(result.Score), Coins: int64(result.Coins), Balance: result.Balance, Served: int32(result.Served), Lost: int32(result.Lost), Wrong: int32(result.Wrong), Level: int32(result.Level)}, nil
}
