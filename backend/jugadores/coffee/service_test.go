package coffee

import (
	"context"
	"database/sql"
	"fmt"
	_ "github.com/lib/pq"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"os"
	"pixelpenguin/platform/coffeegame"
	"sync"
	"testing"
	"time"
)

func bot(plan coffeegame.Plan) []coffeegame.Action {
	engine := coffeegame.NewEngine(plan)
	var actions []coffeegame.Action
	for at := 100; at < coffeegame.Duration; at += 100 {
		engine.Advance(at)
		if engine.Cooldown > 0 {
			continue
		}
		for _, drop := range plan.Drops {
			if drop.At <= at && at < drop.Until && engine.Collected[drop.Kind] < coffeegame.Recipes[engine.Recipe][drop.Kind] {
				action := coffeegame.Action{ID: drop.ID, At: at}
				if engine.Click(action) == nil {
					actions = append(actions, action)
				}
				if engine.Cooldown > 0 {
					break
				}
			}
		}
	}
	return actions
}
func TestDatabaseRewardsAreAtomicAndIdempotent(t *testing.T) {
	if os.Getenv("COFFEE_DB_TEST") != "1" {
		t.Skip("opt-in DB test")
	}
	dsn := fmt.Sprintf("host=%s port=5432 user=%s password=%s dbname=%s sslmode=disable", os.Getenv("DB_HOST"), os.Getenv("DB_USER"), os.Getenv("DB_PASSWORD"), os.Getenv("DB_NAME"))
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	var id int64
	if err = db.QueryRow("INSERT INTO jugadores(nombre,monedas) VALUES('coffee_reward_test',100) RETURNING id").Scan(&id); err != nil {
		t.Fatal(err)
	}
	defer db.Exec("DELETE FROM jugadores WHERE id=$1", id)
	now := time.Now()
	service := New(db)
	service.Now = func() time.Time { return now }
	plan, err := service.Start(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	actions := bot(plan)
	expected, err := coffeegame.Replay(plan, actions)
	if err != nil || expected.Coins == 0 {
		t.Fatalf("acciones de prueba: %+v %v", expected, err)
	}
	if _, err = service.Finish(ctx, id, plan.ID, actions); status.Code(err) != codes.FailedPrecondition {
		t.Fatal("cobro adelantado aceptado")
	}
	now = now.Add(61 * time.Second)
	if _, err = service.Finish(ctx, id+1000000, plan.ID, actions); err == nil {
		t.Fatal("otro jugador cobró la partida")
	}
	if _, err = service.Finish(ctx, id, plan.ID, []coffeegame.Action{{ID: 99999, At: 1}}); status.Code(err) != codes.InvalidArgument {
		t.Fatal("acciones falsas aceptadas")
	}
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := service.Finish(ctx, id, plan.ID, actions)
			if err != nil || result.Coins != expected.Coins {
				t.Errorf("cobro concurrente: %+v %v", result, err)
			}
		}()
	}
	wg.Wait()
	var balance int64
	if err = db.QueryRow("SELECT monedas FROM jugadores WHERE id=$1", id).Scan(&balance); err != nil {
		t.Fatal(err)
	}
	if balance != 100+int64(expected.Coins) {
		t.Fatalf("premio duplicado: saldo %d", balance)
	}
	result, err := service.Finish(ctx, id, plan.ID, nil)
	if err != nil || result.Balance != balance || result.Score != expected.Score {
		t.Fatal("reintento no devuelve el resultado guardado")
	}
	abandoned, _ := service.Start(ctx, id)
	_, err = service.Start(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = service.Finish(ctx, id, abandoned.ID, nil); status.Code(err) != codes.FailedPrecondition {
		t.Fatal("partida abandonada pagada")
	}
	t.Logf("saldo inicial 100, premio único %d, 16 cobros concurrentes, saldo final %d", expected.Coins, balance)
}
