package main

import (
	"context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"log"
	"middleware/api"
	"middleware/plaza"
	"net/http"
	"os"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"time"
)

func main() {
	target := os.Getenv("GRPC_GATEWAY_ADDR")
	if target == "" {
		log.Fatal("GRPC_GATEWAY_ADDR is required")
	}
	connection, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithDisableRetry())
	if err != nil {
		log.Fatal(err)
	}
	defer connection.Close()
	handler := api.New(pb.NewPlayersClient(connection), pb.NewStoreClient(connection), pb.NewCafeteriaClient(connection), pb.NewAuthClient(connection))
	mux := http.NewServeMux()
	hub := plaza.NewHub()
	stopChat, err := hub.StartKafka(context.Background(), os.Getenv("KAFKA_REST_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer stopChat()
	mux.Handle("/plaza", hub.Handler(pb.NewAuthClient(connection)))
	mux.Handle("/", handler)
	server := &http.Server{Addr: ":8000", Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second}
	log.Fatal(server.ListenAndServe())
}
