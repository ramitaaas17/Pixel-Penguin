// Package messaging connects durable database queues to Kafka REST.
package messaging

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const media = "application/vnd.kafka.v2+json"
const jsonMedia = "application/vnd.kafka.json.v2+json"

type queue struct {
	db            *sql.DB
	service, base string
	client        *http.Client
}

// Start installs transactional change capture, then runs producer and consumer.
// Only domain IDs and operations are captured, never passwords or sessions.
func Start(db *sql.DB, service, table string) (func(), error) {
	allowed := map[string]string{"jugadores": "jugadores", "tienda": "productos", "cafeteria": "pedidos"}
	if table == "" || allowed[service] != table {
		return nil, fmt.Errorf("servicio no válido")
	}
	q := &queue{db, service, strings.TrimRight(os.Getenv("KAFKA_REST_URL"), "/"), &http.Client{Timeout: 15 * time.Second}}
	if q.base == "" {
		return nil, fmt.Errorf("falta KAFKA_REST_URL")
	}
	tx, err := db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	_, err = tx.Exec(`SELECT pg_advisory_xact_lock(739182);
 CREATE TABLE IF NOT EXISTS message_outbox (id BIGSERIAL PRIMARY KEY, payload JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
 CREATE TABLE IF NOT EXISTS message_inbox (event_id TEXT PRIMARY KEY, payload JSONB NOT NULL, received_at TIMESTAMPTZ NOT NULL DEFAULT now());
 CREATE OR REPLACE FUNCTION enqueue_domain_change() RETURNS trigger AS $$
 DECLARE row_id BIGINT;
 BEGIN
 IF TG_OP = 'DELETE' THEN row_id := OLD.id; ELSE row_id := NEW.id; END IF;
 INSERT INTO message_outbox(payload) VALUES (jsonb_build_object('tabla',TG_TABLE_NAME,'operacion',TG_OP,'registro_id',row_id));
 RETURN NULL;
 END; $$ LANGUAGE plpgsql;
 DROP TRIGGER IF EXISTS domain_message ON ` + table + `;
 CREATE TRIGGER domain_message AFTER INSERT OR UPDATE OR DELETE ON ` + table + ` FOR EACH ROW EXECUTE FUNCTION enqueue_domain_change();`)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); q.loop(ctx, q.publish) }()
	go func() { defer wg.Done(); q.loop(ctx, q.consume) }()
	return func() { cancel(); wg.Wait() }, nil
}
func (q *queue) request(ctx context.Context, method, path, kind string, body, result any) error {
	var data []byte
	var err error
	if body != nil {
		data, err = json.Marshal(body)
		if err != nil {
			return err
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, q.base+path, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", kind)
	// Produce replies use the generic v2 type. Only record fetches return
	// the embedded JSON media type used by their values.
	accept := media
	if method == http.MethodGet && strings.Contains(path, "/records?") {
		accept = jsonMedia
	}
	req.Header.Set("Accept", accept)
	resp, err := q.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var detail struct {
			Code    int    `json:"error_code"`
			Message string `json:"message"`
		}
		_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&detail)
		return fmt.Errorf("Kafka REST %s %s HTTP %d código %d: %s", method, path, resp.StatusCode, detail.Code, detail.Message)
	}
	if result != nil {
		return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(result)
	}
	return nil
}
func (q *queue) loop(ctx context.Context, work func(context.Context) error) {
	for ctx.Err() == nil {
		if err := work(ctx); err != nil && ctx.Err() == nil {
			log.Printf("mensajería %s: %v", q.service, err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}
func (q *queue) publish(ctx context.Context) error {
	tx, err := q.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var id int64
	var payload json.RawMessage
	err = tx.QueryRowContext(ctx, `SELECT id,payload FROM message_outbox ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&id, &payload)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	value := map[string]any{"id": fmt.Sprintf("%s-%d", q.service, id), "servicio": q.service, "datos": payload}
	body := map[string]any{"records": []any{map[string]any{"key": q.service, "value": value}}}
	var reply struct {
		Offsets []struct {
			ErrorCode *int `json:"error_code"`
		} `json:"offsets"`
	}
	if err = q.request(ctx, "POST", "/topics/pixelpenguin."+q.service, jsonMedia, body, &reply); err != nil {
		return err
	}
	if len(reply.Offsets) != 1 {
		return fmt.Errorf("Kafka no confirmó el mensaje")
	}
	if code := reply.Offsets[0].ErrorCode; code != nil && *code != 0 {
		return fmt.Errorf("Kafka error %d", *code)
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM message_outbox WHERE id=$1`, id); err != nil {
		return err
	}
	return tx.Commit()
}
func (q *queue) consume(ctx context.Context) error {
	group := "/consumers/pixelpenguin-" + q.service
	var consumer struct {
		Instance string `json:"instance_id"`
	}
	if err := q.request(ctx, "POST", group, media, map[string]any{"format": "json", "auto.offset.reset": "earliest", "auto.commit.enable": "false"}, &consumer); err != nil {
		return err
	}
	if consumer.Instance == "" {
		return fmt.Errorf("consumidor sin id")
	}
	path := group + "/instances/" + consumer.Instance
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = q.request(cleanup, "DELETE", path, media, nil, nil)
	}()
	if err := q.request(ctx, "POST", path+"/subscription", media, map[string]any{"topics": []string{"pixelpenguin." + q.service}}, nil); err != nil {
		return err
	}
	for ctx.Err() == nil {
		var records []struct {
			Value json.RawMessage `json:"value"`
		}
		if err := q.request(ctx, "GET", path+"/records?timeout=1000&max_bytes=1048576", jsonMedia, nil, &records); err != nil {
			return err
		}
		for _, record := range records {
			var event struct {
				ID string `json:"id"`
			}
			if err := json.Unmarshal(record.Value, &event); err != nil {
				return err
			}
			if event.ID == "" {
				return fmt.Errorf("mensaje sin id")
			}
			if _, err := q.db.ExecContext(ctx, `INSERT INTO message_inbox(event_id,payload) VALUES ($1,$2) ON CONFLICT DO NOTHING`, event.ID, string(record.Value)); err != nil {
				return err
			}
		}
		// Acknowledge after storage. A repeated delivery has the same primary key.
		if len(records) > 0 {
			if err := q.request(ctx, "POST", path+"/offsets", media, nil, nil); err != nil {
				return err
			}
		}
	}
	return ctx.Err()
}
