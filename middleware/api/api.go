package api

import (
	"context"
	"encoding/json"
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"io"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"strconv"
	"strings"
	"time"
)

type API struct {
	players   pb.PlayersClient
	store     pb.StoreClient
	cafeteria pb.CafeteriaClient
	auth      pb.AuthClient
}

func New(players pb.PlayersClient, store pb.StoreClient, cafeteria pb.CafeteriaClient, auth pb.AuthClient) http.Handler {
	api := &API{players: players, store: store, cafeteria: cafeteria, auth: auth}
	mux := http.NewServeMux()
	mux.HandleFunc("/auth/", api.authHandler)
	mux.HandleFunc("/minijuegos/cafe", api.coffeeHandler)
	mux.HandleFunc("/minijuegos/cafe/", api.coffeeHandler)
	mux.HandleFunc("/heartbeat", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("application alive")) })
	for _, route := range []string{"/jugadores", "/jugadores/"} {
		mux.HandleFunc(route, api.playersHandler)
	}
	for _, route := range []string{"/tienda", "/tienda/"} {
		mux.HandleFunc(route, api.storeHandler)
	}
	for _, route := range []string{"/cafeteria", "/cafeteria/"} {
		mux.HandleFunc(route, api.cafeteriaHandler)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		values := r.Header.Values("Authorization")
		if len(values) > 1 {
			writeError(w, http.StatusUnauthorized, "Sesión inválida")
			return
		}
		if len(values) == 1 {
			ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", values[0]))
		}
		mux.ServeHTTP(w, r.WithContext(ctx))
	})
}
func resourceID(path, prefix string) (int64, error) {
	if path == prefix {
		return 0, nil
	}
	raw := strings.TrimPrefix(path, prefix+"/")
	id, err := strconv.ParseInt(raw, 10, 32)
	if err != nil || id <= 0 {
		return 0, fmt.Errorf("ID inválido")
	}
	return id, nil
}
func readBody(w http.ResponseWriter, r *http.Request, body any) bool {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(body); err != nil {
		writeError(w, http.StatusBadRequest, "Datos de solicitud inválidos")
		return false
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		writeError(w, http.StatusBadRequest, "Datos de solicitud inválidos")
		return false
	}
	return true
}
func writeError(w http.ResponseWriter, code int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
func reply(w http.ResponseWriter, result any, err error, successCode int, headers metadata.MD) {
	if names := headers.Get("x-instance-name"); len(names) > 0 {
		w.Header().Set("X-Instance-Name", names[0])
	}
	if err != nil {
		code, message := http.StatusInternalServerError, "No se pudo completar la operación"
		switch status.Code(err) {
		case codes.InvalidArgument:
			code, message = http.StatusBadRequest, status.Convert(err).Message()
		case codes.NotFound:
			code, message = http.StatusNotFound, "Registro no encontrado"
		case codes.AlreadyExists:
			code, message = http.StatusConflict, "El registro ya existe"
		case codes.Unauthenticated:
			code, message = http.StatusUnauthorized, "Inicia sesión para continuar"
		case codes.PermissionDenied:
			code, message = http.StatusForbidden, "Operación no permitida"
		case codes.Unavailable:
			code, message = http.StatusServiceUnavailable, "Servicio no disponible"
		case codes.DeadlineExceeded:
			code, message = http.StatusGatewayTimeout, "Se agotó el tiempo de la solicitud"
		case codes.FailedPrecondition:
			code, message = http.StatusConflict, status.Convert(err).Message()
		case codes.ResourceExhausted:
			code, message = http.StatusTooManyRequests, "Intenta de nuevo en un momento"
		case codes.Canceled:
			code, message = http.StatusRequestTimeout, "Solicitud cancelada"
		}
		writeError(w, code, message)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(successCode)
	json.NewEncoder(w).Encode(result)
}
func playerJSON(record *pb.Player) map[string]any {
	return map[string]any{"id": record.Id, "nombre": record.Name, "monedas": record.Coins}
}
func productJSON(record *pb.Product) map[string]any {
	return map[string]any{"id": record.Id, "nombre": record.Name, "precio": record.Price, "stock": record.Stock}
}
func orderJSON(record *pb.Order) map[string]any {
	result := map[string]any{"id": record.Id, "producto": record.Product, "cantidad": record.Quantity, "estado": record.Status}
	if record.PlayerId != 0 {
		result["jugador_id"] = record.PlayerId
	}
	return result
}
