package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"pixelpenguin/platform/messaging"
	"pixelpenguin/platform/registry"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
	"tienda/models"
	backendrpc "tienda/rpc"

	_ "github.com/lib/pq"
)

func main() {
	dbHost := os.Getenv("DB_HOST")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	dbPort := os.Getenv("DB_PORT")

	cadenaConexion := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable connect_timeout=5", dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err := sql.Open("postgres", cadenaConexion)
	if err != nil {
		log.Fatal("no se pudo abrir la base de datos: ", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	startupContext, cancelStartup := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancelStartup()
	for {
		if err := db.PingContext(startupContext); err == nil {
			break
		}
		select {
		case <-startupContext.Done():
			log.Fatal("base de datos no disponible durante el arranque")
		case <-time.After(time.Second):
		}
	}

	authConnection, err := grpc.NewClient(os.Getenv("GRPC_GATEWAY_ADDR"), grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithDisableRetry())
	if err != nil {
		log.Fatal(err)
	}
	defer authConnection.Close()
	stopMessages, err := messaging.Start(db, "tienda", "productos")
	if err != nil {
		log.Fatal("no se pudo iniciar mensajería: ", err)
	}
	defer stopMessages()
	grpcServer := grpc.NewServer(grpc.MaxRecvMsgSize(64<<10), grpc.UnaryInterceptor(rpcutil.InstanceHeader(os.Getenv("INSTANCE_NAME"))))
	pb.RegisterStoreServer(grpcServer, backendrpc.New(&models.ProductoModel{Db: db}, pb.NewAuthClient(authConnection)))
	rpcutil.RegisterHealth(grpcServer, db)
	mux := http.NewServeMux()
	mux.HandleFunc("/heartbeat", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.PingContext(ctx); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("service ready"))
	})

	fmt.Println("servicio de tienda: HTTP 8080 y gRPC 9090")
	server := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second}
	if err := registry.Serve(server, grpcServer); err != nil {
		log.Fatal(err)
	}
}
