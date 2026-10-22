package registry

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEnsureRegistration(t *testing.T) {
	for _, testCase := range []struct {
		name                    string
		status                  int
		existing                string
		wantRegister, wantError bool
	}{
		{"missing", 404, "", true, false},
		{"unchanged", 200, `{"Service":"tienda","Address":"10.0.0.2","Port":8080}`, false, false},
		{"new IP after recreation", 200, `{"Service":"tienda","Address":"10.0.0.1","Port":8080}`, true, false},
		{"registry failure", 500, "", false, true},
		{"malformed response", 200, `{`, false, true},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			registrations := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method == http.MethodGet {
					w.WriteHeader(testCase.status)
					w.Write([]byte(testCase.existing))
					return
				}
				if r.Method != http.MethodPut || r.URL.Path != "/v1/agent/service/register" {
					t.Errorf("unexpected request %s %s", r.Method, r.URL)
					w.WriteHeader(400)
					return
				}
				var payload Registration
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Error(err)
				}
				if payload.ID != "tienda-1" || payload.Check.Status != "critical" {
					t.Errorf("invalid registration %+v", payload)
				}
				registrations++
			}))
			defer server.Close()
			client := New(server.URL, Registration{ID: "tienda-1", Name: "tienda", Address: "10.0.0.2", Port: 8080, Check: HealthCheck{Status: "critical"}})
			err := client.Ensure(context.Background())
			if (err != nil) != testCase.wantError {
				t.Fatalf("error=%v", err)
			}
			if (registrations == 1) != testCase.wantRegister {
				t.Errorf("registrations=%d", registrations)
			}
		})
	}
}

func TestDeregisterUsesInstanceID(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.Method != http.MethodPut || r.URL.Path != "/v1/agent/service/deregister/tienda-1" {
			t.Errorf("unexpected deregistration %s %s", r.Method, r.URL)
		}
	}))
	defer server.Close()
	if err := New(server.URL, Registration{ID: "tienda-1"}).Deregister(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("deregister was not sent")
	}
}
