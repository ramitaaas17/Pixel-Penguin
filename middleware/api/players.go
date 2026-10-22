package api

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

func (api *API) playersHandler(w http.ResponseWriter, r *http.Request) {
	id, err := resourceID(r.URL.Path, "/jugadores")
	if err != nil {
		writeError(w, http.StatusBadRequest, "ID inválido")
		return
	}
	var headers metadata.MD
	var result any
	code := http.StatusOK
	switch {
	case id == 0 && r.Method == http.MethodGet:
		var response *pb.PlayerList
		response, err = api.players.ListPlayers(r.Context(), &pb.Empty{}, grpc.Header(&headers))
		if err == nil {
			records := make([]map[string]any, 0, len(response.Players))
			for _, record := range response.Players {
				records = append(records, playerJSON(record))
			}
			result = records
		}
	case id > 0 && r.Method == http.MethodGet:
		var response *pb.Player
		response, err = api.players.GetPlayer(r.Context(), &pb.IdRequest{Id: id}, grpc.Header(&headers))
		if err == nil {
			result = playerJSON(response)
		}
	case id == 0 && r.Method == http.MethodPost:
		var body struct {
			Nombre  string `json:"nombre"`
			Monedas int64  `json:"monedas"`
		}
		if !readBody(w, r, &body) {
			return
		}
		var response *pb.Player
		response, err = api.players.CreatePlayer(r.Context(), &pb.CreatePlayerRequest{Name: body.Nombre, Coins: body.Monedas}, grpc.Header(&headers))
		if err == nil {
			result = playerJSON(response)
		}
		code = http.StatusCreated
	case id > 0 && r.Method == http.MethodPut:
		var body struct {
			Monedas *int64 `json:"monedas"`
		}
		if !readBody(w, r, &body) {
			return
		}
		if body.Monedas == nil {
			writeError(w, http.StatusBadRequest, "Falta el valor que se desea actualizar")
			return
		}
		var response *pb.Player
		response, err = api.players.UpdateCoins(r.Context(), &pb.UpdateCoinsRequest{Id: id, Coins: *body.Monedas}, grpc.Header(&headers))
		if err == nil {
			result = playerJSON(response)
		}
	default:
		w.Header().Set("Allow", "GET, POST, PUT")
		writeError(w, http.StatusMethodNotAllowed, "Método no permitido")
		return
	}
	reply(w, result, err, code, headers)
}
