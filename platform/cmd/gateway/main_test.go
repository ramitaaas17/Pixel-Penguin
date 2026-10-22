package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"text/template"
)

func TestDiscoverOnlyPassingAndStableOrder(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("passing") != "true" || r.URL.Query().Get("tag") != "grpc" {
			t.Errorf("missing health/protocol filter: %s", r.URL)
		}
		w.Write([]byte(`[{"Service":{"Address":"10.0.0.3","Port":8080}},{"Service":{"Address":"10.0.0.2","Port":8080}},{"Service":{"Address":"10.0.0.3","Port":8080}}]`))
	}))
	defer server.Close()
	services, err := discover(context.Background(), server.Client(), server.URL)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range serviceNames {
		if !reflect.DeepEqual(services[name], []string{"10.0.0.2:8080", "10.0.0.3:8080"}) {
			t.Errorf("unstable endpoints: %v", services[name])
		}
	}
}

func TestDiscoverRejectsInvalidResponses(t *testing.T) {
	for _, body := range []string{`{`, `[{"Service":{"Address":"host; injected","Port":8080}}]`, `[{"Service":{"Address":"10.0.0.2","Port":0}}]`} {
		t.Run(body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(body)) }))
			defer server.Close()
			if _, err := discover(context.Background(), server.Client(), server.URL); err == nil {
				t.Fatal("invalid registry response accepted")
			}
		})
	}
}

func TestRenderEmptyPoolHasNoStaticBackendFallback(t *testing.T) {
	configTemplate, err := template.New("nginx.conf.tmpl").Funcs(template.FuncMap{"serviceNames": func() []string { return serviceNames }}).ParseFiles("../../../nginx/nginx.conf.tmpl")
	if err != nil {
		t.Fatal(err)
	}
	output, err := render(configTemplate, snapshot{"tienda": {"10.0.0.2:8080"}})
	if err != nil {
		t.Fatal(err)
	}
	config := string(output)
	if !strings.Contains(config, "server 10.0.0.2:8080") || !strings.Contains(config, "server 127.0.0.1:9") || strings.Contains(config, "tienda-service-1") {
		t.Fatal("unexpected fallback routing")
	}
}
