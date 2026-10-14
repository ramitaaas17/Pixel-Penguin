package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"jugadores/controllers"
	"jugadores/models"

	_ "github.com/lib/pq"
)

func main() {
	dbHost := os.Getenv("DB_HOST")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	dbPort := os.Getenv("DB_PORT")

	cadenaConexion := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable", dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", cadenaConexion)
	if err != nil {
		log.Fatal("no se pudo abrir la base de datos: ", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatal("no se pudo conectar a la base de datos: ", err)
	}

	jugadorModel := &models.JugadorModel{Db: db}
	jugadorController := &controllers.JugadorController{JugadorModel: jugadorModel}

	mux := http.NewServeMux()
	mux.HandleFunc("/jugadores", jugadorController.ManejarJugadores)
	mux.HandleFunc("/jugadores/", jugadorController.ManejarJugadorPorId)
	mux.HandleFunc("/heartbeat", jugadorController.ManejarHeartbeat)

	fmt.Println("servicio de jugadores escuchando en el puerto 8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
