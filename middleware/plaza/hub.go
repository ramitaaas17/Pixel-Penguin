package plaza

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"math"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

type Player struct {
	ID     int64   `json:"id"`
	Name   string  `json:"name"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Moving bool    `json:"moving"`
	Left   bool    `json:"left"`
}
type Message struct {
	Sequence uint64 `json:"sequence"`
	PlayerID int64  `json:"playerId"`
	Name     string `json:"name"`
	Text     string `json:"text"`
	SentAt   int64  `json:"sentAt"`
}
type command struct {
	Type   string  `json:"type"`
	Token  string  `json:"token,omitempty"`
	Text   string  `json:"text,omitempty"`
	X      float64 `json:"x,omitempty"`
	Y      float64 `json:"y,omitempty"`
	Moving bool    `json:"moving,omitempty"`
	Left   bool    `json:"left,omitempty"`
}
type Hub struct {
	mu       sync.Mutex
	peers    map[int64]*peer
	history  []Message
	sequence uint64
	epoch    string
}

func NewHub() *Hub {
	var random [12]byte
	if _, err := rand.Read(random[:]); err != nil {
		panic(err)
	}
	return &Hub{peers: make(map[int64]*peer), epoch: hex.EncodeToString(random[:])}
}
func (hub *Hub) join(p *peer) bool {
	hub.mu.Lock()
	defer hub.mu.Unlock()
	previous := hub.peers[p.player.ID]
	if previous == nil && len(hub.peers) >= 128 {
		return false
	}
	if previous != nil {
		p.player = previous.player
		p.lastMove = previous.lastMove
		previous.stop(4009, "Otra ventana tomó la conexión")
	}
	hub.peers[p.player.ID] = p
	players := make([]Player, 0, len(hub.peers))
	for _, member := range hub.peers {
		players = append(players, member.player)
	}
	sort.Slice(players, func(i, j int) bool { return players[i].ID < players[j].ID })
	history := append([]Message{}, hub.history...)
	p.send(map[string]any{"type": "welcome", "epoch": hub.epoch, "selfId": p.player.ID, "players": players, "history": history})
	hub.broadcast(map[string]any{"type": "joined", "player": p.player})
	return true
}
func (hub *Hub) leave(p *peer) {
	hub.mu.Lock()
	defer hub.mu.Unlock()
	if hub.peers[p.player.ID] != p {
		return
	}
	delete(hub.peers, p.player.ID)
	hub.broadcast(map[string]any{"type": "left", "playerId": p.player.ID})
}
func (hub *Hub) broadcast(event any) {
	data, _ := json.Marshal(event)
	for _, member := range hub.peers {
		member.enqueue(data)
	}
}
func validText(text string) bool {
	if !utf8.ValidString(text) || utf8.RuneCountInString(text) > 180 || text == "" {
		return false
	}
	for _, char := range text {
		if unicode.IsControl(char) || unicode.In(char, unicode.Cf) {
			return false
		}
	}
	return true
}
func validPosition(x, y float64) bool {
	if math.IsNaN(x) || math.IsNaN(y) || math.IsInf(x, 0) || math.IsInf(y, 0) {
		return false
	}
	return x*x/(410*410)+(y-5)*(y-5)/(165*165) <= 1.03
}
func (hub *Hub) handle(p *peer, request command, now time.Time) {
	hub.mu.Lock()
	defer hub.mu.Unlock()
	if hub.peers[p.player.ID] != p {
		return
	}
	switch request.Type {
	case "chat":
		text := strings.TrimSpace(request.Text)
		if !validText(text) {
			p.problem("Usa entre 1 y 180 caracteres, sin saltos de línea.")
			return
		}
		elapsed := now.Sub(p.lastChat).Seconds()
		p.chatCredit = math.Min(3, p.chatCredit+elapsed)
		p.lastChat = now
		if p.chatCredit < 1 {
			p.problem("Espera un momento antes de enviar otro mensaje.")
			return
		}
		p.chatCredit--
		hub.sequence++
		message := Message{Sequence: hub.sequence, PlayerID: p.player.ID, Name: p.player.Name, Text: text, SentAt: now.UnixMilli()}
		hub.history = append(hub.history, message)
		if len(hub.history) > 50 {
			hub.history = hub.history[len(hub.history)-50:]
		}
		hub.broadcast(map[string]any{"type": "chat", "message": message})
	case "move":
		elapsed := now.Sub(p.lastMove).Seconds()
		if elapsed < 0.08 {
			return
		}
		if !validPosition(request.X, request.Y) || math.Hypot(request.X-p.player.X, request.Y-p.player.Y) > 160*math.Min(elapsed, 1)+8 {
			p.send(map[string]any{"type": "correction", "player": p.player})
			return
		}
		p.player.X, p.player.Y = request.X, request.Y
		p.player.Moving, p.player.Left = request.Moving, request.Left
		p.lastMove = now
		hub.broadcast(map[string]any{"type": "moved", "player": p.player})
	default:
		p.problem("Mensaje no reconocido.")
	}
}
