package models

import (
	"context"
	"database/sql"
)

type Pedido struct {
	Id        int    `json:"id"`
	Producto  string `json:"producto"`
	Cantidad  int    `json:"cantidad"`
	Estado    string `json:"estado"`
	JugadorId int64  `json:"jugador_id,omitempty"`
}

type PedidoModel struct {
	Db *sql.DB
}

func (m *PedidoModel) ObtenerTodos(ctx context.Context, playerID int64) ([]Pedido, error) {
	rows, err := m.Db.QueryContext(ctx, "SELECT id, producto, cantidad, estado, COALESCE(jugador_id,0) FROM pedidos WHERE jugador_id=$1", playerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pedidos []Pedido
	for rows.Next() {
		var p Pedido
		if err := rows.Scan(&p.Id, &p.Producto, &p.Cantidad, &p.Estado, &p.JugadorId); err != nil {
			return nil, err
		}
		pedidos = append(pedidos, p)
	}
	return pedidos, rows.Err()
}

func (m *PedidoModel) ObtenerPorId(ctx context.Context, id int) (*Pedido, error) {
	var p Pedido
	consulta := "SELECT id, producto, cantidad, estado, COALESCE(jugador_id,0) FROM pedidos WHERE id = $1"
	err := m.Db.QueryRowContext(ctx, consulta, id).Scan(&p.Id, &p.Producto, &p.Cantidad, &p.Estado, &p.JugadorId)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (m *PedidoModel) Crear(ctx context.Context, producto string, cantidad int, playerID int64) (*Pedido, error) {
	var nuevoId int
	consulta := "INSERT INTO pedidos (producto, cantidad, estado, jugador_id) VALUES ($1, $2, 'pendiente', NULLIF($3,0)) RETURNING id"
	err := m.Db.QueryRowContext(ctx, consulta, producto, cantidad, playerID).Scan(&nuevoId)
	if err != nil {
		return nil, err
	}
	return &Pedido{Id: nuevoId, Producto: producto, Cantidad: cantidad, Estado: "pendiente", JugadorId: playerID}, nil
}
