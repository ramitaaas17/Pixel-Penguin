package api

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"strings"
)

func (api *API) coffeeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeError(w, 405, "Método no permitido")
		return
	}
	var headers metadata.MD
	if r.URL.Path == "/minijuegos/cafe" {
		response, err := api.players.StartCoffeeGame(r.Context(), &pb.Empty{}, grpc.Header(&headers))
		var result any
		if err == nil {
			drops := make([]map[string]int32, 0, len(response.Drops))
			for _, drop := range response.Drops {
				drops = append(drops, map[string]int32{"id": drop.Id, "kind": drop.Kind, "at_ms": drop.AtMs, "until_ms": drop.UntilMs})
			}
			result = map[string]any{"run_id": response.RunId, "duration_ms": response.DurationMs, "recipes": response.Recipes, "drops": drops}
		}
		reply(w, result, err, 201, headers)
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/minijuegos/cafe/"), "/")
	if len(parts) != 2 || len(parts[0]) != 32 || parts[1] != "finalizar" {
		writeError(w, 404, "Ruta no encontrada")
		return
	}
	var body struct {
		Actions []struct {
			ID int32 `json:"drop_id"`
			At int32 `json:"at_ms"`
		} `json:"actions"`
	}
	if !readBody(w, r, &body) {
		return
	}
	if len(body.Actions) > 128 {
		writeError(w, 400, "Demasiadas acciones")
		return
	}
	request := &pb.FinishCoffeeRequest{RunId: parts[0]}
	for _, action := range body.Actions {
		request.Actions = append(request.Actions, &pb.CoffeeAction{DropId: action.ID, AtMs: action.At})
	}
	response, err := api.players.FinishCoffeeGame(r.Context(), request, grpc.Header(&headers))
	var result any
	if err == nil {
		result = map[string]any{"score": response.Score, "coins": response.Coins, "balance": response.Balance, "served": response.Served, "lost": response.Lost, "wrong": response.Wrong, "level": response.Level}
	}
	reply(w, result, err, 200, headers)
}
