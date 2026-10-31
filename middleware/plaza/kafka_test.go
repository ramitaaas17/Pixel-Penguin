package plaza

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"github.com/gorilla/websocket"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func replyJSON(value any) *http.Response {
	data, _ := json.Marshal(value)
	return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(string(data)))}
}
func waitFor(t *testing.T, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("timeout esperando Kafka simulado")
}

func TestKafkaRoundTripIsRequiredForChat(t *testing.T) {
	hub := NewHub()
	p, q := testPeer(1), testPeer(2)
	hub.join(p)
	hub.join(q)
	chatMessages(p)
	chatMessages(q)
	var mu sync.Mutex
	var stored []chatEvent
	var release, failProduce bool
	broker := &chatKafka{hub: hub, base: "http://kafka.test", queue: make(chan chatEvent, 128)}
	broker.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		mu.Lock()
		defer mu.Unlock()
		path := r.URL.Path
		switch {
		case strings.HasPrefix(path, "/topics/"):
			if failProduce {
				return nil, errors.New("Kafka offline")
			}
			if path != "/topics/"+chatTopic || r.Header.Get("Content-Type") != kafkaJSON {
				t.Error("tópico/media incorrectos")
			}
			var body struct {
				Records []struct {
					Partition int       `json:"partition"`
					Key       string    `json:"key"`
					Value     chatEvent `json:"value"`
				} `json:"records"`
			}
			data, _ := io.ReadAll(r.Body)
			if strings.Contains(string(data), "token") {
				t.Error("token enviado a Kafka")
			}
			if err := json.Unmarshal(data, &body); err != nil {
				return nil, err
			}
			if len(body.Records) != 1 || body.Records[0].Partition != 0 || body.Records[0].Key != "plaza" {
				t.Error("partición o clave incorrectas")
			}
			stored = append(stored, body.Records[0].Value)
			return replyJSON(map[string]any{"offsets": []any{map[string]any{"partition": 0, "offset": len(stored) - 1, "error_code": nil}}}), nil
		case strings.HasSuffix(path, "/records"):
			if r.Header.Get("Accept") != kafkaJSON {
				t.Error("Accept incorrecto")
			}
			records := []any{}
			if release && len(stored) > 0 {
				// Kafka can repeat records after consumer recreation.
				event := stored[0]
				records = append(records, map[string]any{"topic": chatTopic, "partition": 0, "offset": 0, "value": event}, map[string]any{"topic": chatTopic, "partition": 0, "offset": 0, "value": event})
			}
			return replyJSON(records), nil
		case strings.HasPrefix(path, "/consumers/") && !strings.Contains(path, "/instances/"):
			return replyJSON(map[string]any{"instance_id": "test"}), nil
		default:
			return replyJSON(map[string]any{}), nil
		}
	})}
	hub.publish = broker.enqueue
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { _ = broker.consume(ctx); close(done) }()
	defer func() { cancel(); <-done }()
	waitFor(t, broker.ready.Load)
	hub.handle(p, command{Type: "chat", Text: "¡Hola, pingüino!"}, time.Now())
	waitFor(t, func() bool { mu.Lock(); defer mu.Unlock(); return len(stored) == 1 })
	if len(chatMessages(p)) != 0 || len(chatMessages(q)) != 0 {
		t.Fatal("mensaje mostrado antes de consumir Kafka")
	}
	mu.Lock()
	release = true
	mu.Unlock()
	waitFor(t, func() bool { hub.mu.Lock(); defer hub.mu.Unlock(); return hub.delivered == 1 })
	for _, member := range []*peer{p, q} {
		messages := chatMessages(member)
		if len(messages) != 1 || messages[0].Text != "¡Hola, pingüino!" || messages[0].PlayerID != 1 || messages[0].Name != "Nieve" {
			t.Fatalf("mensaje duplicado o identidad incorrecta: %+v", messages)
		}
	}
	mu.Lock()
	failProduce = true
	mu.Unlock()
	hub.handle(p, command{Type: "chat", Text: "No debe llegar"}, time.Now())
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("no terminó al fallar Kafka")
	}
	// Do not wait for done again in defer: a closed channel remains readable.
	if len(chatMessages(q)) != 0 {
		t.Fatal("fallo de Kafka produjo mensaje visible")
	}
	foundError := false
	for len(p.outgoing) > 0 {
		var frame map[string]any
		_ = json.Unmarshal(<-p.outgoing, &frame)
		if frame["type"] == "error" {
			foundError = true
		}
	}
	if !foundError {
		t.Fatal("no se informó el fallo al emisor")
	}
}

func TestKafkaRejectsReplayExpiredAndInvalidEvents(t *testing.T) {
	hub := NewHub()
	p := testPeer(1)
	hub.join(p)
	chatMessages(p)
	hub.sequence = 4
	now := time.Now()
	message := Message{Sequence: 1, PlayerID: 1, Name: "Nieve", Text: "hola", SentAt: now.UnixMilli()}
	for _, kind := range []string{"epoch", "expired", "future", "invalid"} {
		event := chatEvent{Epoch: hub.epoch, Message: message}
		switch kind {
		case "epoch":
			event.Epoch = "otro reinicio"
		case "expired":
			event.Message.SentAt = now.Add(-time.Minute).UnixMilli()
		case "future":
			event.Message.Sequence = 5
		case "invalid":
			event.Message.Text = "hola\nmundo"
		}
		hub.deliverKafka(event, now)
	}
	if len(chatMessages(p)) != 0 {
		t.Fatal("evento inválido distribuido")
	}
	hub.deliverKafka(chatEvent{Epoch: hub.epoch, Message: message}, now)
	hub.deliverKafka(chatEvent{Epoch: hub.epoch, Message: message}, now)
	if len(chatMessages(p)) != 1 {
		t.Fatal("evento repetido distribuido dos veces")
	}
}

func TestKafkaUnavailableDoesNotBlockMovement(t *testing.T) {
	hub := NewHub()
	p := testPeer(1)
	hub.join(p)
	chatMessages(p)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	stop, err := hub.StartKafka(ctx, "http://unused.test")
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	hub.handle(p, command{Type: "chat", Text: "hola"}, time.Now())
	hub.handle(p, command{Type: "move", X: -40, Y: 140, Moving: true}, time.Now().Add(time.Second))
	if p.player.X != -40 {
		t.Fatal("Kafka bloqueó el movimiento")
	}
	if len(chatMessages(p)) != 0 {
		t.Fatal("chat eludió Kafka")
	}
	broker := &chatKafka{hub: hub, queue: make(chan chatEvent, 1)}
	broker.ready.Store(true)
	if !broker.enqueue(Message{}) || broker.enqueue(Message{}) {
		t.Fatal("cola no está acotada")
	}
}

func TestKafkaResumeUsesLastDeliveredOffset(t *testing.T) {
	hub := NewHub()
	next := int64(43)
	broker := &chatKafka{hub: hub, base: "http://kafka.test", queue: make(chan chatEvent, 1), next: &next, initialized: true}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	positioned := false
	broker.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/positions/end"):
			t.Error("recuperación omitió mensajes pendientes")
		case strings.HasSuffix(r.URL.Path, "/positions"):
			var body struct {
				Offsets []struct {
					Offset int64 `json:"offset"`
				} `json:"offsets"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			positioned = len(body.Offsets) == 1 && body.Offsets[0].Offset == 43
		case strings.HasSuffix(r.URL.Path, "/records"):
			cancel()
			return replyJSON([]any{}), nil
		}
		return replyJSON(map[string]any{"instance_id": "resume"}), nil
	})}
	_ = broker.consume(ctx)
	if !positioned {
		t.Fatal("no retomó el offset")
	}
}

// Opt-in integration test: real Kafka REST plus two real WebSocket clients.
// The auth fixture supplies test identities without creating database accounts.
func TestKafkaLiveWebSocket(t *testing.T) {
	base := os.Getenv("KAFKA_REST_URL")
	if base == "" {
		t.Skip("requiere KAFKA_REST_URL y tópico pixelpenguin.chat")
	}
	hub := NewHub()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stop, err := hub.StartKafka(ctx, base)
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	server := httptest.NewServer(hub.Handler(testAuth{}))
	defer server.Close()
	socketURL := "ws" + strings.TrimPrefix(server.URL, "http")
	var clients []*websocket.Conn
	for _, id := range []byte{101, 102} {
		c, _, err := websocket.DefaultDialer.Dial(socketURL, nil)
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		raw := make([]byte, 32)
		raw[0] = id
		if err := c.WriteJSON(map[string]any{"type": "auth", "token": base64.RawURLEncoding.EncodeToString(raw)}); err != nil {
			t.Fatal(err)
		}
		welcome := readType(t, c, "welcome")
		if len(welcome["history"].([]any)) != 0 {
			t.Fatal("se reprodujo historial")
		}
		clients = append(clients, c)
	}
	// Probe through the actual publisher until the consumer is ready. Rejected
	// attempts return errors; the accepted event must then return through Kafka.
	deadline := time.Now().Add(20 * time.Second)
	for {
		if err := clients[0].WriteJSON(map[string]any{"type": "chat", "text": "¡Hola, pingüino por Kafka!"}); err != nil {
			t.Fatal(err)
		}
		clients[0].SetReadDeadline(time.Now().Add(6 * time.Second))
		var frame map[string]any
		for {
			if err := clients[0].ReadJSON(&frame); err != nil {
				t.Fatal(err)
			}
			if frame["type"] == "chat" || frame["type"] == "error" {
				break
			}
		}
		if frame["type"] == "chat" {
			message := frame["message"].(map[string]any)
			if message["text"] != "¡Hola, pingüino por Kafka!" || message["playerId"] != float64(101) {
				t.Fatal("mensaje propio incorrecto")
			}
			remote := readType(t, clients[1], "chat")["message"].(map[string]any)
			if remote["sequence"] != message["sequence"] || remote["text"] != message["text"] {
				t.Fatal("clientes recibieron mensajes distintos")
			}
			t.Log("Kafka real: dos WebSockets reciben el mismo mensaje español con identidad y secuencia")
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("Kafka no quedó listo")
		}
		time.Sleep(time.Second)
	}
	if err := clients[1].WriteJSON(map[string]any{"type": "chat", "text": "¡Recibido desde el segundo jugador!"}); err != nil {
		t.Fatal(err)
	}
	for _, c := range clients {
		message := readType(t, c, "chat")["message"].(map[string]any)
		if message["playerId"] != float64(102) {
			t.Fatal("respuesta sin identidad del segundo jugador")
		}
	}
	t.Log("Kafka real: respuesta bidireccional correcta")
}
