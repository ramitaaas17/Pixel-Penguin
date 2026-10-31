package coffee

import (
	"bytes"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"pixelpenguin/platform/coffeegame"
	"testing"
	"time"
)

func TestHTTPRewardRoundTrip(t *testing.T) {
	if os.Getenv("COFFEE_HTTP_TEST") != "1" {
		t.Skip("opt-in real HTTP/gRPC/database test (60 s)")
	}
	client := &http.Client{Timeout: 10 * time.Second}
	base := "http://gateway:8000"
	request := func(path, token string, body any, result any) int {
		t.Helper()
		data, _ := json.Marshal(body)
		method := "POST"
		if body == nil {
			method = "GET"
		}
		req, err := http.NewRequest(method, base+path, bytes.NewReader(data))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if result != nil {
			if err = json.NewDecoder(resp.Body).Decode(result); err != nil {
				t.Fatal(err)
			}
		} else {
			_, _ = io.Copy(io.Discard, resp.Body)
		}
		return resp.StatusCode
	}
	if request("/minijuegos/cafe", "", map[string]any{}, nil) != 401 {
		t.Fatal("partida anónima con premio permitida")
	}
	var raw [16]byte
	_, _ = rand.Read(raw[:])
	username := "cf_" + hex.EncodeToString(raw[:6])
	password := hex.EncodeToString(raw[:])
	var account struct {
		Token  string `json:"token"`
		Player struct {
			ID    int64 `json:"id"`
			Coins int64 `json:"monedas"`
		} `json:"jugador"`
	}
	credentials := map[string]any{"username": username, "password": password}
	if request("/auth/register", "", credentials, &account) != 201 {
		t.Fatal("registro temporal falló")
	}
	db, err := sql.Open("postgres", fmt.Sprintf("host=%s port=5432 user=%s password=%s dbname=%s sslmode=disable", os.Getenv("DB_HOST"), os.Getenv("DB_USER"), os.Getenv("DB_PASSWORD"), os.Getenv("DB_NAME")))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	defer func() {
		_, err := db.Exec("DELETE FROM accounts WHERE player_id=$1;", account.Player.ID)
		if err != nil {
			t.Error(err)
		}
		_, err = db.Exec("DELETE FROM jugadores WHERE id=$1", account.Player.ID)
		if err != nil {
			t.Error(err)
		}
	}()
	var plan coffeegame.Plan
	if request("/minijuegos/cafe", account.Token, map[string]any{}, &plan) != 201 {
		t.Fatal("inicio real HTTP/gRPC falló")
	}
	started := time.Now()
	actions := bot(plan)
	expected, _ := coffeegame.Replay(plan, actions)
	path := "/minijuegos/cafe/" + plan.ID + "/finalizar"
	if request(path, account.Token, map[string]any{"actions": actions}, nil) != 409 {
		t.Fatal("cobro antes del fin del turno")
	}
	if request(path, account.Token, map[string]any{"actions": actions, "score": 999999}, nil) != 400 {
		t.Fatal("se aceptó puntaje suministrado por el cliente")
	}
	t.Log("partida real iniciada; esperando los 60 segundos requeridos por el servidor")
	for stage := 1; stage <= 4; stage++ {
		time.Sleep(time.Until(started.Add(time.Duration(stage) * 15 * time.Second)))
		t.Logf("turno real: %d/60 segundos", stage*15)
	}
	time.Sleep(250 * time.Millisecond)
	var result coffeegame.Result
	if request(path, account.Token, map[string]any{"actions": actions}, &result) != 200 {
		t.Fatal("cobro real falló")
	}
	if result.Score != expected.Score || result.Coins != expected.Coins || result.Balance != account.Player.Coins+int64(expected.Coins) {
		t.Fatalf("resultado incorrecto: %+v, esperado %+v", result, expected)
	}
	var again coffeegame.Result
	if request(path, account.Token, map[string]any{"actions": actions}, &again) != 200 || again.Balance != result.Balance {
		t.Fatal("reintento duplicó monedas")
	}
	var refreshed struct {
		Player struct {
			Coins int64 `json:"monedas"`
		} `json:"jugador"`
	}
	if request("/auth/session", account.Token, nil, &refreshed) != 200 || refreshed.Player.Coins != result.Balance {
		t.Fatal("saldo no persistió en la cuenta")
	}
	t.Logf("HTTP → gRPC → PostgreSQL: %d puntos, %d monedas, saldo %d; reintento sin duplicar", result.Score, result.Coins, result.Balance)
}
