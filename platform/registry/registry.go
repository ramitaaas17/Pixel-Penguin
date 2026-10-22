package registry

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"google.golang.org/grpc"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type Registration struct {
	ID      string
	Name    string
	Address string
	Port    int
	Tags    []string
	Check   HealthCheck
}

type HealthCheck struct {
	HTTP                           string `json:",omitempty"`
	GRPC                           string `json:",omitempty"`
	Interval                       string
	Timeout                        string
	Status                         string
	DeregisterCriticalServiceAfter string
}

type Client struct {
	baseURL      string
	httpClient   *http.Client
	registration Registration
}

func New(baseURL string, registration Registration) *Client {
	return &Client{baseURL: baseURL, httpClient: &http.Client{Timeout: 3 * time.Second}, registration: registration}
}

func (client *Client) request(ctx context.Context, method, path string, payload any) (int, []byte, error) {
	var body io.Reader
	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, err
		}
		body = bytes.NewReader(data)
	}
	request, err := http.NewRequestWithContext(ctx, method, client.baseURL+path, body)
	if err != nil {
		return 0, nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := client.httpClient.Do(request)
	if err != nil {
		return 0, nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 16384))
	return response.StatusCode, data, err
}

func (client *Client) Ensure(ctx context.Context) error {
	status, data, err := client.request(ctx, http.MethodGet, "/v1/agent/service/"+url.PathEscape(client.registration.ID), nil)
	if err != nil {
		return err
	}
	if status == http.StatusOK {
		var existing struct {
			Service string
			Address string
			Port    int
		}
		if err := json.Unmarshal(data, &existing); err != nil {
			return err
		}
		if existing.Service == client.registration.Name && existing.Address == client.registration.Address && existing.Port == client.registration.Port {
			return nil
		}
	}
	if status != http.StatusNotFound && status != http.StatusOK {
		return fmt.Errorf("consul lookup status %d", status)
	}
	status, _, err = client.request(ctx, http.MethodPut, "/v1/agent/service/register?replace-existing-checks=true", client.registration)
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("consul register status %d", status)
	}
	log.Printf("registered service=%s instance=%s", client.registration.Name, client.registration.ID)
	return nil
}

func (client *Client) Deregister(ctx context.Context) error {
	status, _, err := client.request(ctx, http.MethodPut, "/v1/agent/service/deregister/"+url.PathEscape(client.registration.ID), nil)
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("consul deregister status %d", status)
	}
	log.Printf("deregistered instance=%s", client.registration.ID)
	return nil
}

func localAddress() (string, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return "", err
	}
	addresses, err := net.LookupIP(hostname)
	if err != nil {
		return "", err
	}
	for _, address := range addresses {
		if address.To4() != nil && !address.IsLoopback() {
			return address.String(), nil
		}
	}
	return "", fmt.Errorf("no container IPv4 address found")
}

func Serve(server *http.Server, grpcServer *grpc.Server) error {
	baseURL := os.Getenv("CONSUL_HTTP_ADDR")
	name, instanceID := os.Getenv("SERVICE_NAME"), os.Getenv("INSTANCE_NAME")
	if baseURL == "" || name == "" || instanceID == "" {
		return fmt.Errorf("missing Consul service configuration")
	}
	address, err := localAddress()
	if err != nil {
		return err
	}
	listener, err := net.Listen("tcp", ":9090")
	if err != nil {
		return err
	}
	registration := Registration{ID: instanceID, Name: name, Address: address, Port: 9090, Tags: []string{"grpc"}, Check: HealthCheck{
		GRPC: net.JoinHostPort(address, "9090"), Interval: "2s", Timeout: "1s", Status: "critical", DeregisterCriticalServiceAfter: "1m",
	}}
	client := New(baseURL, registration)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	serverErrors := make(chan error, 2)
	go func() { serverErrors <- server.ListenAndServe() }()
	go func() { serverErrors <- grpcServer.Serve(listener) }()
	registryDone := make(chan struct{})
	go func() {
		defer close(registryDone)
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()
		for {
			if err := client.Ensure(ctx); err != nil && ctx.Err() == nil {
				log.Printf("registry unavailable: %v", err)
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	select {
	case err = <-serverErrors:
	case <-ctx.Done():
	}
	stop()
	<-registryDone
	cleanupContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if deregisterError := client.Deregister(cleanupContext); deregisterError != nil {
		log.Printf("deregister failed: %v", deregisterError)
	}
	grpcDone := make(chan struct{})
	go func() { grpcServer.GracefulStop(); close(grpcDone) }()
	shutdownError := server.Shutdown(cleanupContext)
	select {
	case <-grpcDone:
	case <-cleanupContext.Done():
		grpcServer.Stop()
	}
	if shutdownError != nil {
		return shutdownError
	}
	if err == http.ErrServerClosed || err == grpc.ErrServerStopped {
		return nil
	}
	return err
}
