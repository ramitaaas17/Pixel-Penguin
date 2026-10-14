package models

import "database/sql"

type Pedido struct {
	Id       int    `json:"id"`
	Producto string `json:"producto"`
	Cantidad int    `json:"cantidad"`
	Estado   string `json:"estado"`
}

type PedidoModel struct {
	Db *sql.DB
}

func (m *PedidoModel) ObtenerTodos() ([]Pedido, error) {
	rows, err := m.Db.Query("SELECT id, producto, cantidad, estado FROM pedidos")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pedidos []Pedido
	for rows.Next() {
		var p Pedido
		if err := rows.Scan(&p.Id, &p.Producto, &p.Cantidad, &p.Estado); err != nil {
			return nil, err
		}
		pedidos = append(pedidos, p)
	}
	return pedidos, nil
}

func (m *PedidoModel) ObtenerPorId(id int) (*Pedido, error) {
	var p Pedido
	consulta := "SELECT id, producto, cantidad, estado FROM pedidos WHERE id = $1"
	err := m.Db.QueryRow(consulta, id).Scan(&p.Id, &p.Producto, &p.Cantidad, &p.Estado)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (m *PedidoModel) Crear(producto string, cantidad int) (*Pedido, error) {
	var nuevoId int
	consulta := "INSERT INTO pedidos (producto, cantidad, estado) VALUES ($1, $2, 'pendiente') RETURNING id"
	err := m.Db.QueryRow(consulta, producto, cantidad).Scan(&nuevoId)
	if err != nil {
		return nil, err
	}
	return &Pedido{Id: nuevoId, Producto: producto, Cantidad: cantidad, Estado: "pendiente"}, nil
}
