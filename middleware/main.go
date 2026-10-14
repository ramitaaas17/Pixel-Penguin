package main

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync"
)

type ServiceRoute struct {
	Prefix  string   `json:"prefix"`
	Targets []string `json:"targets"`
}

type RoutePool struct {
	Prefix  string
	Proxies []*httputil.ReverseProxy
	Counter int
	Mutex   sync.Mutex
}

func (p *RoutePool) nextProxy() *httputil.ReverseProxy {
	p.Mutex.Lock()
	defer p.Mutex.Unlock()
	proxy := p.Proxies[p.Counter%len(p.Proxies)]
	p.Counter++
	return proxy
}

func loadServices(path string) ([]ServiceRoute, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var routes []ServiceRoute
	if err := json.Unmarshal(data, &routes); err != nil {
		return nil, err
	}
	return routes, nil
}

func buildPools(routes []ServiceRoute) []*RoutePool {
	var pools []*RoutePool
	for _, route := range routes {
		pool := &RoutePool{Prefix: route.Prefix}
		for _, target := range route.Targets {
			targetUrl, err := url.Parse(target)
			if err != nil {
				log.Fatal("invalid target url: ", err)
			}
			pool.Proxies = append(pool.Proxies, httputil.NewSingleHostReverseProxy(targetUrl))
		}
		pools = append(pools, pool)
	}
	return pools
}

func conCORS(siguiente http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		siguiente(w, r)
	}
}

func main() {
	routes, err := loadServices("services.json")
	if err != nil {
		log.Fatal("could not load services.json: ", err)
	}

	pools := buildPools(routes)

	mux := http.NewServeMux()

	mux.HandleFunc("/", conCORS(func(w http.ResponseWriter, r *http.Request) {
		for _, pool := range pools {
			if strings.HasPrefix(r.URL.Path, pool.Prefix) {
				proxy := pool.nextProxy()
				log.Println(r.Method, r.URL.Path, "->", pool.Prefix)
				proxy.ServeHTTP(w, r)
				return
			}
		}
		http.NotFound(w, r)
	}))

	mux.HandleFunc("/heartbeat", conCORS(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("middleware alive"))
	}))

	log.Println("middleware listening on port 8000")
	log.Fatal(http.ListenAndServe(":8000", mux))
}
