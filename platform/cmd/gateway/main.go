package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"sort"
	"strconv"
	"syscall"
	"text/template"
	"time"
)

var serviceNames = []string{"jugadores", "tienda", "cafeteria"}

type snapshot map[string][]string
type serviceEntry struct {
	Service struct {
		Address string
		Port    int
	}
}

func discover(ctx context.Context, client *http.Client, baseURL string) (snapshot, error) {
	result := snapshot{}
	for _, name := range serviceNames {
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/v1/health/service/"+name+"?passing=true&tag=grpc", nil)
		if err != nil {
			return nil, err
		}
		response, err := client.Do(request)
		if err != nil {
			return nil, err
		}
		var entries []serviceEntry
		if response.StatusCode != http.StatusOK {
			response.Body.Close()
			return nil, fmt.Errorf("consul health status %d", response.StatusCode)
		}
		err = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&entries)
		response.Body.Close()
		if err != nil {
			return nil, err
		}
		endpoints := map[string]bool{}
		for _, entry := range entries {
			if net.ParseIP(entry.Service.Address) == nil || entry.Service.Port < 1 || entry.Service.Port > 65535 {
				return nil, fmt.Errorf("invalid endpoint for %s", name)
			}
			endpoints[net.JoinHostPort(entry.Service.Address, strconv.Itoa(entry.Service.Port))] = true
		}
		for endpoint := range endpoints {
			result[name] = append(result[name], endpoint)
		}
		sort.Strings(result[name])
	}
	return result, nil
}

func render(configTemplate *template.Template, services snapshot) ([]byte, error) {
	var output bytes.Buffer
	err := configTemplate.Execute(&output, services)
	return output.Bytes(), err
}

func applyConfig(config []byte, reload bool) error {
	const configPath = "/etc/nginx/nginx.conf"
	const candidatePath = "/etc/nginx/nginx.candidate.conf"
	if err := os.WriteFile(candidatePath, config, 0644); err != nil {
		return err
	}
	validation := exec.Command("nginx", "-t", "-c", candidatePath)
	if output, err := validation.CombinedOutput(); err != nil {
		return fmt.Errorf("invalid nginx config: %s: %w", output, err)
	}
	previous, _ := os.ReadFile(configPath)
	if err := os.Rename(candidatePath, configPath); err != nil {
		return err
	}
	if reload {
		if output, err := exec.Command("nginx", "-s", "reload").CombinedOutput(); err != nil {
			os.WriteFile(configPath, previous, 0644)
			return fmt.Errorf("reload failed: %s: %w", output, err)
		}
	}
	return nil
}

func run(ctx context.Context) error {
	configTemplate, err := template.New("nginx.conf.tmpl").Funcs(template.FuncMap{"serviceNames": func() []string { return serviceNames }}).ParseFiles("/etc/nginx/nginx.conf.tmpl")
	if err != nil {
		return err
	}
	baseURL := os.Getenv("CONSUL_HTTP_ADDR")
	if baseURL == "" {
		return fmt.Errorf("CONSUL_HTTP_ADDR is required")
	}
	client := &http.Client{Timeout: 2 * time.Second}
	services, err := discover(ctx, client, baseURL)
	lastSuccess := time.Now()
	if err != nil {
		log.Printf("initial discovery unavailable: %v", err)
		services = snapshot{}
		lastSuccess = time.Time{}
	}
	currentConfig, err := render(configTemplate, services)
	if err != nil {
		return err
	}
	if err := applyConfig(currentConfig, false); err != nil {
		return err
	}
	nginx := exec.Command("nginx", "-g", "daemon off;")
	nginx.Stdout, nginx.Stderr = os.Stdout, os.Stderr
	if err := nginx.Start(); err != nil {
		return err
	}
	nginxDone := make(chan error, 1)
	go func() { nginxDone <- nginx.Wait() }()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			nginx.Process.Signal(syscall.SIGQUIT)
			select {
			case <-nginxDone:
				return nil
			case <-time.After(5 * time.Second):
				return nginx.Process.Kill()
			}
		case err := <-nginxDone:
			return fmt.Errorf("nginx exited: %v", err)
		case <-ticker.C:
			nextServices, err := discover(ctx, client, baseURL)
			if err != nil {
				if ctx.Err() != nil {
					continue
				}
				log.Printf("discovery unavailable: %v", err)
				if time.Since(lastSuccess) < 10*time.Second {
					continue
				}
				nextServices = snapshot{}
			} else {
				lastSuccess = time.Now()
			}
			nextConfig, err := render(configTemplate, nextServices)
			if err != nil {
				return err
			}
			if bytes.Equal(currentConfig, nextConfig) {
				continue
			}
			if err := applyConfig(nextConfig, true); err != nil {
				log.Printf("configuration rejected: %v", err)
				continue
			}
			currentConfig = nextConfig
			log.Printf("discovery applied jugadores=%v tienda=%v cafeteria=%v", nextServices["jugadores"], nextServices["tienda"], nextServices["cafeteria"])
		}
	}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if err := run(ctx); err != nil {
		log.Fatal(err)
	}
}
