package plaza

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const chatTopic = "pixelpenguin.chat"
const kafkaMedia = "application/vnd.kafka.v2+json"
const kafkaJSON = "application/vnd.kafka.json.v2+json"

type chatEvent struct {
	Epoch   string  `json:"epoch"`
	Message Message `json:"message"`
}

type chatKafka struct {
	hub    *Hub
	base   string
	client *http.Client
	queue  chan chatEvent
	ready  atomic.Bool
	// Only the worker owns the next offset. Keep it across REST consumer recreation.
	next        *int64
	initialized bool
}

// StartKafka must run before exposing the hub. No direct-delivery fallback is
// used when Kafka is configured. The returned function stops the worker.
func (hub *Hub) StartKafka(ctx context.Context, base string) (func(), error) {
	parsed, err := url.Parse(strings.TrimRight(base, "/"))
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return nil, fmt.Errorf("KAFKA_REST_URL debe ser una URL HTTP válida")
	}
	broker := &chatKafka{hub: hub, base: strings.TrimRight(base, "/"), client: &http.Client{Timeout: 5 * time.Second}, queue: make(chan chatEvent, 128)}
	hub.publish = broker.enqueue
	workerCtx, cancel := context.WithCancel(ctx)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() { defer wg.Done(); broker.run(workerCtx) }()
	return func() { cancel(); wg.Wait() }, nil
}

func (broker *chatKafka) enqueue(message Message) bool {
	if !broker.ready.Load() {
		return false
	}
	select {
	case broker.queue <- chatEvent{Epoch: broker.hub.epoch, Message: message}:
		return true
	default:
		return false
	}
}

func (broker *chatKafka) request(ctx context.Context, method, path string, body, result any) error {
	var data []byte
	var err error
	if body != nil {
		data, err = json.Marshal(body)
		if err != nil {
			return err
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, broker.base+path, bytes.NewReader(data))
	if err != nil {
		return err
	}
	kind := kafkaMedia
	if strings.HasPrefix(path, "/topics/") {
		kind = kafkaJSON
	}
	req.Header.Set("Content-Type", kind)
	accept := kafkaMedia
	if method == "GET" && strings.Contains(path, "/records?") {
		accept = kafkaJSON
	}
	req.Header.Set("Accept", accept)
	resp, err := broker.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("Kafka chat %s HTTP %d", method, resp.StatusCode)
	}
	if result != nil {
		return json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(result)
	}
	return nil
}

func (broker *chatKafka) run(ctx context.Context) {
	for ctx.Err() == nil {
		err := broker.consume(ctx)
		broker.ready.Store(false)
		// Drop unsent live messages instead of emitting them long after recovery.
		for len(broker.queue) > 0 {
			broker.failed(<-broker.queue)
		}
		if ctx.Err() != nil {
			return
		}
		log.Printf("chat Kafka: %v", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}
func (broker *chatKafka) failed(event chatEvent) {
	broker.hub.mu.Lock()
	defer broker.hub.mu.Unlock()
	if p := broker.hub.peers[event.Message.PlayerID]; p != nil {
		p.problem("No se pudo enviar el mensaje por Kafka. Inténtalo de nuevo.")
	}
}
func (broker *chatKafka) produce(ctx context.Context, event chatEvent) error {
	var response struct {
		Offsets []struct {
			ErrorCode *int `json:"error_code"`
		} `json:"offsets"`
	}
	body := map[string]any{"records": []any{map[string]any{"partition": 0, "key": "plaza", "value": event}}}
	if err := broker.request(ctx, "POST", "/topics/"+chatTopic, body, &response); err != nil {
		return err
	}
	if len(response.Offsets) != 1 {
		return fmt.Errorf("Kafka no confirmó el mensaje del chat")
	}
	if code := response.Offsets[0].ErrorCode; code != nil && *code != 0 {
		return fmt.Errorf("Kafka chat error %d", *code)
	}
	return nil
}
func (broker *chatKafka) consume(ctx context.Context) error {
	group := "/consumers/pixelpenguin-chat-" + broker.hub.epoch
	var consumer struct {
		Instance string `json:"instance_id"`
	}
	if err := broker.request(ctx, "POST", group, map[string]any{"format": "json", "auto.offset.reset": "latest", "auto.commit.enable": "false"}, &consumer); err != nil {
		return err
	}
	if consumer.Instance == "" {
		return fmt.Errorf("Kafka chat: consumidor sin ID")
	}
	path := group + "/instances/" + url.PathEscape(consumer.Instance)
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = broker.request(cleanup, "DELETE", path, nil, nil)
	}()
	partition := map[string]any{"topic": chatTopic, "partition": 0}
	if err := broker.request(ctx, "POST", path+"/assignments", map[string]any{"partitions": []any{partition}}, nil); err != nil {
		return err
	}
	if broker.next == nil && !broker.initialized {
		if err := broker.request(ctx, "POST", path+"/positions/end", map[string]any{"partitions": []any{partition}}, nil); err != nil {
			return err
		}
	} else if broker.next != nil {
		if err := broker.request(ctx, "POST", path+"/positions", map[string]any{"offsets": []any{map[string]any{"topic": chatTopic, "partition": 0, "offset": *broker.next}}}, nil); err != nil {
			return err
		}
	}
	// Poll once before accepting publishes: seek-to-end is lazy in Kafka clients.
	if err := broker.poll(ctx, path); err != nil {
		return err
	}
	if !broker.initialized {
		// Save the initial live position, even if the topic was empty. If the
		// first produce succeeds but fetching fails, recreation must not skip it.
		if err := broker.request(ctx, "POST", path+"/offsets", nil, nil); err != nil {
			return err
		}
		broker.initialized = true
	}
	broker.ready.Store(true)
	log.Print("chat Kafka: consumidor listo")
	for ctx.Err() == nil {
		for i := 0; i < 16; i++ {
			select {
			case event := <-broker.queue:
				if time.Since(time.UnixMilli(event.Message.SentAt)) > 15*time.Second {
					broker.failed(event)
					continue
				}
				if err := broker.produce(ctx, event); err != nil {
					// A timeout is ambiguous: do not automatically republish and duplicate.
					broker.failed(event)
					return err
				}
			default:
				i = 16
			}
		}
		if err := broker.poll(ctx, path); err != nil {
			return err
		}
	}
	return ctx.Err()
}
func (broker *chatKafka) poll(ctx context.Context, path string) error {
	var records []struct {
		Topic     string    `json:"topic"`
		Partition int       `json:"partition"`
		Offset    int64     `json:"offset"`
		Value     chatEvent `json:"value"`
	}
	if err := broker.request(ctx, "GET", path+"/records?timeout=200&max_bytes=262144", nil, &records); err != nil {
		return err
	}
	for _, record := range records {
		if record.Topic != chatTopic || record.Partition != 0 {
			return fmt.Errorf("Kafka chat: partición inesperada")
		}
		broker.hub.deliverKafka(record.Value, time.Now())
		next := record.Offset + 1
		broker.next = &next
	}
	return nil
}

func (hub *Hub) deliverKafka(event chatEvent, now time.Time) {
	hub.mu.Lock()
	defer hub.mu.Unlock()
	message := event.Message
	if event.Epoch != hub.epoch || message.Sequence <= hub.delivered || message.Sequence > hub.sequence || message.PlayerID <= 0 || !validText(message.Text) || now.Sub(time.UnixMilli(message.SentAt)) > 15*time.Second || message.SentAt > now.Add(time.Second).UnixMilli() {
		return
	}
	hub.delivered = message.Sequence
	hub.broadcast(map[string]any{"type": "chat", "message": message})
}
