package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"cafeteria/controllers"
	"cafeteria/models"

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

	pedidoModel := &models.PedidoModel{Db: db}
	pedidoController := &controllers.PedidoController{PedidoModel: pedidoModel}

	mux := http.NewServeMux()
	mux.HandleFunc("/cafeteria", pedidoController.ManejarPedidos)
	mux.HandleFunc("/cafeteria/", pedidoController.ManejarPedidoPorId)
	mux.HandleFunc("/heartbeat", pedidoController.ManejarHeartbeat)

	fmt.Println("servicio de cafeteria escuchando en el puerto 8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
