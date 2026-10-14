package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"cafeteria/models"
)

type PedidoController struct {
	PedidoModel *models.PedidoModel
}

func (c *PedidoController) ManejarPedidos(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		pedidos, err := c.PedidoModel.ObtenerTodos()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(pedidos)

	case http.MethodPost:
		var cuerpo struct {
			Producto string `json:"producto"`
			Cantidad int    `json:"cantidad"`
		}
		if err := json.NewDecoder(r.Body).Decode(&cuerpo); err != nil {
			http.Error(w, "cuerpo invalido", http.StatusBadRequest)
			return
		}
		nuevoPedido, err := c.PedidoModel.Crear(cuerpo.Producto, cuerpo.Cantidad)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(nuevoPedido)

	default:
		http.Error(w, "metodo no permitido", http.StatusMethodNotAllowed)
	}
}

func (c *PedidoController) ManejarPedidoPorId(w http.ResponseWriter, r *http.Request) {
	idTexto := strings.TrimPrefix(r.URL.Path, "/cafeteria/")
	id, err := strconv.Atoi(idTexto)
	if err != nil {
		http.Error(w, "id invalido", http.StatusBadRequest)
		return
	}

	pedido, err := c.PedidoModel.ObtenerPorId(id)
	if err != nil {
		http.Error(w, "pedido no encontrado", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pedido)
}

func (c *PedidoController) ManejarHeartbeat(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("cafeteria service alive"))
}
