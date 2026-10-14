package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"tienda/models"
)

type ProductoController struct {
	ProductoModel *models.ProductoModel
}

func (c *ProductoController) ManejarProductos(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		productos, err := c.ProductoModel.ObtenerTodos()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(productos)

	case http.MethodPost:
		var cuerpo struct {
			Nombre string  `json:"nombre"`
			Precio float64 `json:"precio"`
			Stock  int     `json:"stock"`
		}
		if err := json.NewDecoder(r.Body).Decode(&cuerpo); err != nil {
			http.Error(w, "cuerpo invalido", http.StatusBadRequest)
			return
		}
		nuevoProducto, err := c.ProductoModel.Crear(cuerpo.Nombre, cuerpo.Precio, cuerpo.Stock)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(nuevoProducto)

	default:
		http.Error(w, "metodo no permitido", http.StatusMethodNotAllowed)
	}
}

func (c *ProductoController) ManejarProductoPorId(w http.ResponseWriter, r *http.Request) {
	idTexto := strings.TrimPrefix(r.URL.Path, "/tienda/")
	id, err := strconv.Atoi(idTexto)
	if err != nil {
		http.Error(w, "id invalido", http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		producto, err := c.ProductoModel.ObtenerPorId(id)
		if err != nil {
			http.Error(w, "producto no encontrado", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(producto)

	case http.MethodPut:
		var cuerpo struct {
			Stock int `json:"stock"`
		}
		if err := json.NewDecoder(r.Body).Decode(&cuerpo); err != nil {
			http.Error(w, "cuerpo invalido", http.StatusBadRequest)
			return
		}
		producto, err := c.ProductoModel.ActualizarStock(id, cuerpo.Stock)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(producto)

	default:
		http.Error(w, "metodo no permitido", http.StatusMethodNotAllowed)
	}
}

func (c *ProductoController) ManejarHeartbeat(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("tienda service alive"))
}
