package plaza

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
)

func testPeer(id int64) *peer {
	now := time.Now()
	return &peer{player: Player{ID: id, Name: "Nieve", X: -32, Y: 148}, outgoing: make(chan []byte, 256), done: make(chan struct{}), lastMove: now, lastChat: now, chatCredit: 3}
}

// Only tests use immediate delivery; production requires Kafka.
func localTestHub() *Hub {
	hub := NewHub()
	hub.publish = func(message Message) bool {
		hub.broadcast(map[string]any{"type": "chat", "message": message})
		return true
	}
	return hub
}
func chatMessages(p *peer) []Message {
	var messages []Message
	for len(p.outgoing) > 0 {
		var frame struct {
			Type    string  `json:"type"`
			Message Message `json:"message"`
		}
		_ = json.Unmarshal(<-p.outgoing, &frame)
		if frame.Type == "chat" {
			messages = append(messages, frame.Message)
		}
	}
	return messages
}
func TestHubLiveOrderingAndReplacement(t *testing.T) {
	hub := localTestHub()
	p := testPeer(1)
	hub.join(p)
	for i := 0; i < 60; i++ {
		hub.handle(p, command{Type: "chat", Text: "¡Hola, pingüinos!"}, time.Now().Add(time.Duration(i)*time.Second))
	}
	messages := chatMessages(p)
	if len(messages) != 60 || messages[0].Sequence != 1 || messages[59].Sequence != 60 {
		t.Fatal("mensajes en vivo sin orden")
	}
	replacement := testPeer(1)
	hub.join(replacement)
	hub.leave(p)
	if len(hub.peers) != 1 || hub.peers[1] != replacement {
		t.Fatal("desconexión vieja eliminó al reemplazo")
	}
	select {
	case <-p.done:
		if p.closeCode != 4009 {
			t.Fatal("código de reemplazo")
		}
	default:
		t.Fatal("conexión anterior sigue activa")
	}
}
func TestValidationRateAndMovement(t *testing.T) {
	hub := localTestHub()
	p := testPeer(1)
	hub.join(p)
	now := time.Now()
	for _, text := range []string{"", strings.Repeat("x", 181), "hola\nmundo", "hola\u202emundo"} {
		hub.handle(p, command{Type: "chat", Text: text}, now)
	}
	if len(chatMessages(p)) != 0 {
		t.Fatal("texto inválido aceptado")
	}
	for i := 0; i < 10; i++ {
		hub.handle(p, command{Type: "chat", Text: "hola"}, now)
	}
	if len(chatMessages(p)) != 3 {
		t.Fatal("no se limita el envío")
	}
	hub.handle(p, command{Type: "move", X: 300, Y: 0}, now.Add(time.Second))
	if p.player.X != -32 {
		t.Fatal("teletransporte permitido")
	}
	hub.handle(p, command{Type: "move", X: -40, Y: 140, Moving: true}, now.Add(time.Second))
	if p.player.X != -40 || !p.player.Moving {
		t.Fatal("movimiento válido rechazado")
	}
	if validPosition(900, 0) {
		t.Fatal("fuera de la plaza")
	}
}
func TestConcurrentMessagesHaveSingleSequence(t *testing.T) {
	hub := localTestHub()
	peers := []*peer{testPeer(1), testPeer(2)}
	for _, p := range peers {
		hub.join(p)
	}
	var workers sync.WaitGroup
	for _, p := range peers {
		workers.Add(1)
		go func(p *peer) {
			defer workers.Done()
			for i := 0; i < 3; i++ {
				hub.handle(p, command{Type: "chat", Text: "Hola"}, time.Now())
			}
		}(p)
	}
	workers.Wait()
	messages := chatMessages(peers[0])
	if len(messages) != 6 {
		t.Fatal("mensajes perdidos")
	}
	for i, m := range messages {
		if m.Sequence != uint64(i+1) {
			t.Fatal("orden inconsistente")
		}
	}
}

type testAuth struct{}

func (testAuth) GetSession(ctx context.Context, _ *pb.Empty, _ ...grpc.CallOption) (*pb.Session, error) {
	md, _ := metadata.FromOutgoingContext(ctx)
	values := md.Get("authorization")
	if len(values) != 1 || !strings.HasPrefix(values[0], "Bearer ") {
		return nil, status.Error(codes.Unauthenticated, "invalid")
	}
	token := strings.TrimPrefix(values[0], "Bearer ")
	raw, _ := base64.RawURLEncoding.DecodeString(token)
	if len(raw) != 32 || raw[0] == 0 {
		return nil, status.Error(codes.Unauthenticated, "invalid")
	}
	return &pb.Session{Player: &pb.Player{Id: int64(raw[0]), Name: "Nieve"}}, nil
}
func readType(t *testing.T, c *websocket.Conn, kind string) map[string]any {
	t.Helper()
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		var event map[string]any
		if err := c.ReadJSON(&event); err != nil {
			t.Fatal(err)
		}
		if event["type"] == kind {
			return event
		}
	}
}
func TestWebSocketAuthBroadcastAndOrigin(t *testing.T) {
	server := httptest.NewServer(localTestHub().Handler(testAuth{}))
	defer server.Close()
	url := "ws" + strings.TrimPrefix(server.URL, "http")
	var clients []*websocket.Conn
	for _, id := range []byte{1, 2} {
		c, _, err := websocket.DefaultDialer.Dial(url, nil)
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		raw := make([]byte, 32)
		raw[0] = id
		c.WriteJSON(map[string]any{"type": "auth", "token": base64.RawURLEncoding.EncodeToString(raw)})
		readType(t, c, "welcome")
		clients = append(clients, c)
	}
	clients[0].WriteJSON(map[string]any{"type": "chat", "text": "¡Hola!"})
	for _, c := range clients {
		message := readType(t, c, "chat")["message"].(map[string]any)
		if message["name"] != "Nieve" || message["playerId"] != float64(1) {
			t.Fatal("identidad sin validar")
		}
	}
	clients[0].WriteJSON(map[string]any{"type": "chat", "text": "suplantación", "name": "Otro"})
	readType(t, clients[0], "error")
	_, response, err := websocket.DefaultDialer.Dial(url, map[string][]string{"Origin": {"https://otro.example"}})
	if err == nil || response.StatusCode != 403 {
		t.Fatal("origen externo aceptado")
	}
	c, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.WriteJSON(map[string]any{"type": "auth", "token": strings.Repeat("A", 43)})
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, _, err = c.ReadMessage()
	if !websocket.IsCloseError(err, 4001) {
		t.Fatalf("token inválido: %v", err)
	}
	var request command
	if decode([]byte(`{"type":"chat"}{"type":"chat"}`), &request) == nil {
		t.Fatal("dos mensajes JSON aceptados")
	}
}
