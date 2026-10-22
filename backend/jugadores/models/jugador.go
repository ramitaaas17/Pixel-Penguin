package models

import (
	"context"
	"database/sql"
)

type Jugador struct {
	Id      int    `json:"id"`
	Nombre  string `json:"nombre"`
	Monedas int    `json:"monedas"`
}

type JugadorModel struct {
	Db *sql.DB
}

func (m *JugadorModel) ObtenerTodos(ctx context.Context) ([]Jugador, error) {
	rows, err := m.Db.QueryContext(ctx, "SELECT id, nombre, monedas FROM jugadores")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var jugadores []Jugador
	for rows.Next() {
		var j Jugador
		if err := rows.Scan(&j.Id, &j.Nombre, &j.Monedas); err != nil {
			return nil, err
		}
		jugadores = append(jugadores, j)
	}
	return jugadores, rows.Err()
}

func (m *JugadorModel) ObtenerPorId(ctx context.Context, id int) (*Jugador, error) {
	var j Jugador
	consulta := "SELECT id, nombre, monedas FROM jugadores WHERE id = $1"
	err := m.Db.QueryRowContext(ctx, consulta, id).Scan(&j.Id, &j.Nombre, &j.Monedas)
	if err != nil {
		return nil, err
	}
	return &j, nil
}

func (m *JugadorModel) Crear(ctx context.Context, nombre string, monedas int) (*Jugador, error) {
	var nuevoId int
	consulta := "INSERT INTO jugadores (nombre, monedas) VALUES ($1, $2) RETURNING id"
	err := m.Db.QueryRowContext(ctx, consulta, nombre, monedas).Scan(&nuevoId)
	if err != nil {
		return nil, err
	}
	return &Jugador{Id: nuevoId, Nombre: nombre, Monedas: monedas}, nil
}

func (m *JugadorModel) ActualizarMonedas(ctx context.Context, id int, monedas int) (*Jugador, error) {
	consulta := "UPDATE jugadores SET monedas = $1 WHERE id = $2"
	if _, err := m.Db.ExecContext(ctx, consulta, monedas, id); err != nil {
		return nil, err
	}
	return m.ObtenerPorId(ctx, id)
}
