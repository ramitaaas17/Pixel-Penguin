package messaging

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRESTRequest(t *testing.T) {
	server := newTestServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Path != "/topics/pixelpenguin.tienda" {
			t.Errorf("unexpected route %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Content-Type") != jsonMedia || r.Header.Get("Accept") != media {
			t.Error("missing Kafka JSON headers")
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if _, ok := body["records"]; !ok {
			t.Error("missing records")
		}
		w.Header().Set("Content-Type", jsonMedia)
		w.Write([]byte(`{"offsets":[{"offset":4,"error_code":null}]}`))
	}))
	defer server.Close()
	q := queue{base: server.URL, client: server.Client()}
	var reply struct{ Offsets []struct{ Offset int } }
	err := q.request(context.Background(), "POST", "/topics/pixelpenguin.tienda", jsonMedia, map[string]any{"records": []any{}}, &reply)
	if err != nil || len(reply.Offsets) != 1 || reply.Offsets[0].Offset != 4 {
		t.Fatalf("invalid response: %+v %v", reply, err)
	}
}
func TestRESTFailureAndCancellation(t *testing.T) {
	server := newTestServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
	defer server.Close()
	q := queue{base: server.URL, client: server.Client()}
	if err := q.request(context.Background(), "GET", "/topics", media, nil, nil); err == nil {
		t.Error("503 must be retried")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := q.request(ctx, "GET", "/topics", media, nil, nil); err == nil {
		t.Error("cancelled request succeeded")
	}
}

func TestConsumerRetriesWithoutCommittingFailedFetch(t *testing.T) {
	subscribed, deleted, committed := false, false, false
	server := newTestServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/consumers/pixelpenguin-tienda":
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			if body["auto.commit.enable"] != "false" {
				t.Error("automatic commits must be disabled")
			}
			w.Write([]byte(`{"instance_id":"test"}`))
		case r.Method == "DELETE":
			deleted = true
			w.WriteHeader(204)
		case r.URL.Path == "/consumers/pixelpenguin-tienda/instances/test/subscription":
			subscribed = true
			w.WriteHeader(204)
		case r.URL.Path == "/consumers/pixelpenguin-tienda/instances/test/records":
			w.WriteHeader(503)
		case r.URL.Path == "/consumers/pixelpenguin-tienda/instances/test/offsets":
			committed = true
			w.WriteHeader(204)
		default:
			t.Errorf("unexpected request %s", r.URL)
		}
	}))
	defer server.Close()
	q := queue{service: "tienda", base: server.URL, client: server.Client()}
	if err := q.consume(context.Background()); err == nil {
		t.Error("failed fetch must trigger reconnection")
	}
	if !subscribed || !deleted || committed {
		t.Fatalf("subscription=%v cleanup=%v commit=%v", subscribed, deleted, committed)
	}
}

// Run the REST contract tests without opening network sockets.
type handlerTransport struct{ handler http.Handler }

func (h handlerTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if err := r.Context().Err(); err != nil {
		return nil, err
	}
	recorder := httptest.NewRecorder()
	h.handler.ServeHTTP(recorder, r)
	return recorder.Result(), nil
}

type testServer struct {
	URL     string
	handler http.Handler
}

func newTestServer(handler http.Handler) *testServer {
	return &testServer{"http://kafka.test", handler}
}
func (s *testServer) Client() *http.Client {
	return &http.Client{Transport: handlerTransport{s.handler}}
}
func (s *testServer) Close() {}
