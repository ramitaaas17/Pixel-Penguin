package api

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"net/http"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

func (api *API) authHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	var headers metadata.MD
	var result any
	var err error
	code := http.StatusOK
	var response *pb.Session
	switch {
	case (r.URL.Path == "/auth/register" || r.URL.Path == "/auth/login") && r.Method == http.MethodPost:
		var body struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if !readBody(w, r, &body) {
			return
		}
		credentials := &pb.Credentials{Username: body.Username, Password: body.Password}
		if r.URL.Path == "/auth/register" {
			response, err = api.auth.Register(r.Context(), credentials, grpc.Header(&headers))
			code = http.StatusCreated
		} else {
			response, err = api.auth.Login(r.Context(), credentials, grpc.Header(&headers))
		}
	case r.URL.Path == "/auth/session" && r.Method == http.MethodGet:
		response, err = api.auth.GetSession(r.Context(), &pb.Empty{}, grpc.Header(&headers))
	case r.URL.Path == "/auth/logout" && r.Method == http.MethodPost:
		_, err = api.auth.Logout(r.Context(), &pb.Empty{}, grpc.Header(&headers))
		result = map[string]bool{"ok": true}
	default:
		writeError(w, http.StatusMethodNotAllowed, "Método no permitido")
		return
	}
	if err != nil && r.URL.Path == "/auth/register" && status.Code(err) == codes.AlreadyExists {
		writeError(w, http.StatusConflict, "Ese nombre de usuario ya está ocupado")
		return
	}
	if err != nil && r.URL.Path == "/auth/login" && status.Code(err) == codes.Unauthenticated {
		writeError(w, http.StatusUnauthorized, "Usuario o contraseña incorrectos")
		return
	}
	if err == nil && response != nil {
		data := map[string]any{"jugador": playerJSON(response.Player), "expires_at": response.ExpiresAt}
		if response.Token != "" {
			data["token"] = response.Token
		}
		result = data
	}
	w.Header().Set("Cache-Control", "no-store")
	reply(w, result, err, code, headers)
}
