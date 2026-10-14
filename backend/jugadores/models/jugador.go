package models

import "database/sql"

type Jugador struct {
	Id      int    `json:"id"`
	Nombre  string `json:"nombre"`
	Monedas int    `json:"monedas"`
}

type JugadorModel struct {
	Db *sql.DB
}

func (m *JugadorModel) ObtenerTodos() ([]Jugador, error) {
	rows, err := m.Db.Query("SELECT id, nombre, monedas FROM jugadores")
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
	return jugadores, nil
}

func (m *JugadorModel) ObtenerPorId(id int) (*Jugador, error) {
	var j Jugador
	consulta := "SELECT id, nombre, monedas FROM jugadores WHERE id = $1"
	err := m.Db.QueryRow(consulta, id).Scan(&j.Id, &j.Nombre, &j.Monedas)
	if err != nil {
		return nil, err
	}
	return &j, nil
}

func (m *JugadorModel) Crear(nombre string, monedas int) (*Jugador, error) {
	var nuevoId int
	consulta := "INSERT INTO jugadores (nombre, monedas) VALUES ($1, $2) RETURNING id"
	err := m.Db.QueryRow(consulta, nombre, monedas).Scan(&nuevoId)
	if err != nil {
		return nil, err
	}
	return &Jugador{Id: nuevoId, Nombre: nombre, Monedas: monedas}, nil
}

func (m *JugadorModel) ActualizarMonedas(id int, monedas int) (*Jugador, error) {
	consulta := "UPDATE jugadores SET monedas = $1 WHERE id = $2"
	if _, err := m.Db.Exec(consulta, monedas, id); err != nil {
		return nil, err
	}
	return m.ObtenerPorId(id)
}
