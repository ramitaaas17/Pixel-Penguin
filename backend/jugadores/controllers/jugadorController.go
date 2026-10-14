package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"jugadores/models"
)

type JugadorController struct {
	JugadorModel *models.JugadorModel
}

func (c *JugadorController) ManejarJugadores(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		jugadores, err := c.JugadorModel.ObtenerTodos()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(jugadores)

	case http.MethodPost:
		var cuerpo struct {
			Nombre  string `json:"nombre"`
			Monedas int    `json:"monedas"`
		}
		if err := json.NewDecoder(r.Body).Decode(&cuerpo); err != nil {
			http.Error(w, "cuerpo invalido", http.StatusBadRequest)
			return
		}
		nuevoJugador, err := c.JugadorModel.Crear(cuerpo.Nombre, cuerpo.Monedas)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(nuevoJugador)

	default:
		http.Error(w, "metodo no permitido", http.StatusMethodNotAllowed)
	}
}

func (c *JugadorController) ManejarJugadorPorId(w http.ResponseWriter, r *http.Request) {
	idTexto := strings.TrimPrefix(r.URL.Path, "/jugadores/")
	id, err := strconv.Atoi(idTexto)
	if err != nil {
		http.Error(w, "id invalido", http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		jugador, err := c.JugadorModel.ObtenerPorId(id)
		if err != nil {
			http.Error(w, "jugador no encontrado", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(jugador)

	case http.MethodPut:
		var cuerpo struct {
			Monedas int `json:"monedas"`
		}
		if err := json.NewDecoder(r.Body).Decode(&cuerpo); err != nil {
			http.Error(w, "cuerpo invalido", http.StatusBadRequest)
			return
		}
		jugador, err := c.JugadorModel.ActualizarMonedas(id, cuerpo.Monedas)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(jugador)

	default:
		http.Error(w, "metodo no permitido", http.StatusMethodNotAllowed)
	}
}

func (c *JugadorController) ManejarHeartbeat(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("jugadores service alive"))
}
