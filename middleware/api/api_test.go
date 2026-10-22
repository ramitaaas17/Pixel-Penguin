package api

import (
	"context"
	"encoding/json"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
	"net"
	"net/http/httptest"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
	"strings"
	"testing"
)

type playersServer struct {
	pb.UnimplementedPlayersServer
	err   error
	empty bool
}

func (server *playersServer) ListPlayers(ctx context.Context, request *pb.Empty) (*pb.PlayerList, error) {
	if server.err != nil {
		return nil, server.err
	}
	if server.empty {
		return &pb.PlayerList{}, nil
	}
	return &pb.PlayerList{Players: []*pb.Player{{Id: 1, Name: "Pingüino", Coins: 0}}}, nil
}
func TestHTTPAdapterPreservesJSONAndMapsRPCFailures(t *testing.T) {
	listener := bufconn.Listen(1 << 20)
	server := grpc.NewServer(grpc.UnaryInterceptor(rpcutil.InstanceHeader("test-instance")))
	backend := &playersServer{}
	pb.RegisterPlayersServer(server, backend)
	go server.Serve(listener)
	defer server.Stop()
	connection, err := grpc.NewClient("passthrough:///local", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return listener.DialContext(ctx) }))
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	handler := New(pb.NewPlayersClient(connection), nil, nil, nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest("GET", "/jugadores", nil))
	var records []map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &records); err != nil {
		t.Fatal(err)
	}
	if response.Code != 200 || records[0]["monedas"] != float64(0) || records[0]["nombre"] != "Pingüino" || response.Header().Get("X-Instance-Name") != "test-instance" {
		t.Fatalf("incompatible JSON or metadata: %s", response.Body)
	}
	backend.empty = true
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest("GET", "/jugadores", nil))
	if strings.TrimSpace(response.Body.String()) != "[]" {
		t.Fatalf("empty list must be an array: %s", response.Body)
	}
	for _, testCase := range []struct {
		code     codes.Code
		httpCode int
	}{{codes.Unavailable, 503}, {codes.NotFound, 404}, {codes.DeadlineExceeded, 504}, {codes.Internal, 500}} {
		backend.err = status.Error(testCase.code, "private detail")
		response = httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest("GET", "/jugadores", nil))
		if response.Code != testCase.httpCode || strings.Contains(response.Body.String(), "private detail") {
			t.Fatalf("unsafe or incorrect HTTP error: %d %s", response.Code, response.Body)
		}
	}
	for _, body := range []string{"null", "{}", "{\"monedas\":1}{}"} {
		response = httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest("PUT", "/jugadores/1", strings.NewReader(body)))
		if response.Code != 400 {
			t.Fatalf("invalid update accepted: %s", body)
		}
	}
}
