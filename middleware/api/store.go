package api

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

func (api *API) storeHandler(w http.ResponseWriter, r *http.Request) {
	id, err := resourceID(r.URL.Path, "/tienda")
	if err != nil {
		writeError(w, http.StatusBadRequest, "ID inválido")
		return
	}
	var headers metadata.MD
	var result any
	code := http.StatusOK
	switch {
	case id == 0 && r.Method == http.MethodGet:
		var response *pb.ProductList
		response, err = api.store.ListProducts(r.Context(), &pb.Empty{}, grpc.Header(&headers))
		if err == nil {
			records := make([]map[string]any, 0, len(response.Products))
			for _, record := range response.Products {
				records = append(records, productJSON(record))
			}
			result = records
		}
	case id > 0 && r.Method == http.MethodGet:
		var response *pb.Product
		response, err = api.store.GetProduct(r.Context(), &pb.IdRequest{Id: id}, grpc.Header(&headers))
		if err == nil {
			result = productJSON(response)
		}
	case id == 0 && r.Method == http.MethodPost:
		var body struct {
			Nombre string  `json:"nombre"`
			Precio float64 `json:"precio"`
			Stock  int64   `json:"stock"`
		}
		if !readBody(w, r, &body) {
			return
		}
		var response *pb.Product
		response, err = api.store.CreateProduct(r.Context(), &pb.CreateProductRequest{Name: body.Nombre, Price: body.Precio, Stock: body.Stock}, grpc.Header(&headers))
		if err == nil {
			result = productJSON(response)
		}
		code = http.StatusCreated
	case id > 0 && r.Method == http.MethodPut:
		var body struct {
			Stock *int64 `json:"stock"`
		}
		if !readBody(w, r, &body) {
			return
		}
		if body.Stock == nil {
			writeError(w, http.StatusBadRequest, "Falta el valor que se desea actualizar")
			return
		}
		var response *pb.Product
		response, err = api.store.UpdateStock(r.Context(), &pb.UpdateStockRequest{Id: id, Stock: *body.Stock}, grpc.Header(&headers))
		if err == nil {
			result = productJSON(response)
		}
	default:
		w.Header().Set("Allow", "GET, POST, PUT")
		writeError(w, http.StatusMethodNotAllowed, "Método no permitido")
		return
	}
	reply(w, result, err, code, headers)
}
