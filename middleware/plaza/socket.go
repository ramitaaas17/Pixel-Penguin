package plaza

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/session"
)

type peer struct {
	conn        *websocket.Conn
	outgoing    chan []byte
	done        chan struct{}
	once        sync.Once
	closeCode   int
	closeReason string
	token       string
	player      Player
	lastMove    time.Time
	lastChat    time.Time
	chatCredit  float64
}

func (p *peer) stop(code int, reason string) {
	p.once.Do(func() { p.closeCode, p.closeReason = code, reason; close(p.done) })
}
func (p *peer) enqueue(data []byte) {
	select {
	case p.outgoing <- data:
	default:
		p.stop(1013, "Conexión demasiado lenta")
	}
}
func (p *peer) send(event any)      { data, _ := json.Marshal(event); p.enqueue(data) }
func (p *peer) problem(text string) { p.send(map[string]any{"type": "error", "text": text}) }
func decode(data []byte, value any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return err
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return io.ErrUnexpectedEOF
	}
	return nil
}
func authenticate(auth session.Validator, token string) (*pb.Session, error) {
	if _, err := session.Hash(token); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", "Bearer "+token))
	return auth.GetSession(ctx, &pb.Empty{})
}
func (hub *Hub) Handler(auth session.Validator) http.Handler {
	upgrader := websocket.Upgrader{HandshakeTimeout: 5 * time.Second, ReadBufferSize: 2048, WriteBufferSize: 4096}
	slots := make(chan struct{}, 160)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Método no permitido", 405)
			return
		}
		if r.URL.RawQuery != "" {
			http.Error(w, "No envíes credenciales en la URL", 400)
			return
		}
		select {
		case slots <- struct{}{}:
			defer func() { <-slots }()
		default:
			http.Error(w, "Sala ocupada", 503)
			return
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		conn.SetReadLimit(2048)
		conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		kind, data, err := conn.ReadMessage()
		var first struct {
			Type  string `json:"type"`
			Token string `json:"token"`
		}
		if err != nil || kind != websocket.TextMessage || decode(data, &first) != nil || first.Type != "auth" {
			conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1008, "Inicia sesión para entrar"), time.Now().Add(time.Second))
			return
		}
		identity, err := authenticate(auth, first.Token)
		if err != nil {
			code, reason := 1013, "No se pudo validar la sesión"
			if status.Code(err) == codes.Unauthenticated {
				code, reason = 4001, "Tu sesión terminó"
			}
			conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(code, reason), time.Now().Add(time.Second))
			return
		}
		now := time.Now()
		p := &peer{conn: conn, outgoing: make(chan []byte, 128), done: make(chan struct{}), token: first.Token, player: Player{ID: identity.Player.Id, Name: identity.Player.Name, X: -32, Y: 148}, lastMove: now, lastChat: now, chatCredit: 3}
		go p.writeLoop(auth)
		defer p.stop(1000, "Hasta pronto")
		if !hub.join(p) {
			p.stop(1013, "La plaza está llena")
			return
		}
		defer hub.leave(p)
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		conn.SetPongHandler(func(string) error { return conn.SetReadDeadline(time.Now().Add(60 * time.Second)) })
		lastWindow, count := now, 0
		for {
			kind, data, err = conn.ReadMessage()
			if err != nil {
				return
			}
			if kind != websocket.TextMessage {
				p.stop(1008, "Usa mensajes de texto")
				return
			}
			now = time.Now()
			if now.Sub(lastWindow) >= time.Second {
				lastWindow, count = now, 0
			}
			count++
			if count > 30 {
				p.stop(1008, "Demasiadas solicitudes")
				return
			}
			var request command
			if decode(data, &request) != nil || request.Token != "" {
				p.problem("Datos inválidos.")
				continue
			}
			hub.handle(p, request, now)
		}
	})
}
func (p *peer) writeLoop(auth session.Validator) {
	defer p.conn.Close()
	ping := time.NewTicker(20 * time.Second)
	validate := time.NewTicker(5 * time.Second)
	defer ping.Stop()
	defer validate.Stop()
	for {
		select {
		case <-p.done:
			p.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(p.closeCode, p.closeReason), time.Now().Add(time.Second))
			return
		case data := <-p.outgoing:
			p.conn.SetWriteDeadline(time.Now().Add(3 * time.Second))
			if p.conn.WriteMessage(websocket.TextMessage, data) != nil {
				return
			}
		case <-ping.C:
			if p.conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(time.Second)) != nil {
				return
			}
		case <-validate.C:
			if _, err := authenticate(auth, p.token); err != nil {
				code, reason := 1013, "No se pudo validar la sesión"
				if status.Code(err) == codes.Unauthenticated {
					code, reason = 4001, "Tu sesión terminó"
				}
				p.stop(code, reason)
			}
		}
	}
}
