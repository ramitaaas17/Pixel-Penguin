package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"tienda/controllers"
	"tienda/models"

	_ "github.com/lib/pq"
)

func conEncabezadoInstancia(nombreInstancia string, siguiente http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Instance-Name", nombreInstancia)
		log.Println(nombreInstancia, "atendio", r.Method, r.URL.Path)
		siguiente(w, r)
	}
}

func main() {
	dbHost := os.Getenv("DB_HOST")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	dbPort := os.Getenv("DB_PORT")
	nombreInstancia := os.Getenv("INSTANCE_NAME")

	cadenaConexion := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable", dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", cadenaConexion)
	if err != nil {
		log.Fatal("no se pudo abrir la base de datos: ", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatal("no se pudo conectar a la base de datos: ", err)
	}

	productoModel := &models.ProductoModel{Db: db}
	productoController := &controllers.ProductoController{ProductoModel: productoModel}

	mux := http.NewServeMux()
	mux.HandleFunc("/tienda", conEncabezadoInstancia(nombreInstancia, productoController.ManejarProductos))
	mux.HandleFunc("/tienda/", conEncabezadoInstancia(nombreInstancia, productoController.ManejarProductoPorId))
	mux.HandleFunc("/heartbeat", productoController.ManejarHeartbeat)

	fmt.Println("servicio de tienda", nombreInstancia, "escuchando en el puerto 8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
