package api

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

func (api *API) cafeteriaHandler(w http.ResponseWriter, r *http.Request) {
	id, err := resourceID(r.URL.Path, "/cafeteria")
	if err != nil {
		writeError(w, http.StatusBadRequest, "ID inválido")
		return
	}
	var headers metadata.MD
	var result any
	code := http.StatusOK
	switch {
	case id == 0 && r.Method == http.MethodGet:
		var response *pb.OrderList
		response, err = api.cafeteria.ListOrders(r.Context(), &pb.Empty{}, grpc.Header(&headers))
		if err == nil {
			records := make([]map[string]any, 0, len(response.Orders))
			for _, record := range response.Orders {
				records = append(records, orderJSON(record))
			}
			result = records
		}
	case id > 0 && r.Method == http.MethodGet:
		var response *pb.Order
		response, err = api.cafeteria.GetOrder(r.Context(), &pb.IdRequest{Id: id}, grpc.Header(&headers))
		if err == nil {
			result = orderJSON(response)
		}
	case id == 0 && r.Method == http.MethodPost:
		var body struct {
			Producto  string `json:"producto"`
			Cantidad  int32  `json:"cantidad"`
			JugadorId int64  `json:"jugador_id"`
		}
		if !readBody(w, r, &body) {
			return
		}
		var response *pb.Order
		response, err = api.cafeteria.CreateOrder(r.Context(), &pb.CreateOrderRequest{Product: body.Producto, Quantity: body.Cantidad, PlayerId: body.JugadorId}, grpc.Header(&headers))
		if err == nil {
			result = orderJSON(response)
		}
		code = http.StatusCreated
	default:
		w.Header().Set("Allow", "GET, POST")
		writeError(w, http.StatusMethodNotAllowed, "Método no permitido")
		return
	}
	reply(w, result, err, code, headers)
}
