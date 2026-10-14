package models

import "database/sql"

type Producto struct {
	Id     int     `json:"id"`
	Nombre string  `json:"nombre"`
	Precio float64 `json:"precio"`
	Stock  int     `json:"stock"`
}

type ProductoModel struct {
	Db *sql.DB
}

func (m *ProductoModel) ObtenerTodos() ([]Producto, error) {
	rows, err := m.Db.Query("SELECT id, nombre, precio, stock FROM productos")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var productos []Producto
	for rows.Next() {
		var p Producto
		if err := rows.Scan(&p.Id, &p.Nombre, &p.Precio, &p.Stock); err != nil {
			return nil, err
		}
		productos = append(productos, p)
	}
	return productos, nil
}

func (m *ProductoModel) ObtenerPorId(id int) (*Producto, error) {
	var p Producto
	consulta := "SELECT id, nombre, precio, stock FROM productos WHERE id = $1"
	err := m.Db.QueryRow(consulta, id).Scan(&p.Id, &p.Nombre, &p.Precio, &p.Stock)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (m *ProductoModel) Crear(nombre string, precio float64, stock int) (*Producto, error) {
	var nuevoId int
	consulta := "INSERT INTO productos (nombre, precio, stock) VALUES ($1, $2, $3) RETURNING id"
	err := m.Db.QueryRow(consulta, nombre, precio, stock).Scan(&nuevoId)
	if err != nil {
		return nil, err
	}
	return &Producto{Id: nuevoId, Nombre: nombre, Precio: precio, Stock: stock}, nil
}

func (m *ProductoModel) ActualizarStock(id int, stock int) (*Producto, error) {
	consulta := "UPDATE productos SET stock = $1 WHERE id = $2"
	if _, err := m.Db.Exec(consulta, stock, id); err != nil {
		return nil, err
	}
	return m.ObtenerPorId(id)
}
