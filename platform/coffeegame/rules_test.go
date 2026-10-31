package coffeegame

import (
	"encoding/json"
	"os"
	"testing"
)

// BotActions exercises the rules using only visible, still-needed ingredients.
func BotActions(plan Plan) []Action {
	e := NewEngine(plan)
	var actions []Action
	for at := 100; at < Duration; at += 100 {
		e.Advance(at)
		if e.Cooldown > 0 {
			continue
		}
		for _, drop := range plan.Drops {
			if drop.At <= at && at < drop.Until && !e.clicked[drop.ID] && e.Collected[drop.Kind] < Recipes[e.Recipe][drop.Kind] {
				action := Action{ID: drop.ID, At: at}
				if e.Click(action) == nil {
					actions = append(actions, action)
				}
				if e.Cooldown > 0 {
					break
				}
			}
		}
	}
	return actions
}
func TestReplayRewardsAndValidation(t *testing.T) {
	plan, err := NewPlan()
	if err != nil {
		t.Fatal(err)
	}
	actions := BotActions(plan)
	result, err := Replay(plan, actions)
	if err != nil || result.Served < 1 || result.Coins != min(50, result.Score/100) || result.Score <= 0 {
		t.Fatalf("resultado %+v: %v", result, err)
	}
	if _, err = Replay(plan, []Action{{ID: 0, At: 0}, {ID: 0, At: 1}}); err == nil {
		t.Fatal("clic duplicado aceptado")
	}
	if _, err = Replay(plan, []Action{{ID: 99999, At: 1}}); err == nil {
		t.Fatal("ingrediente inventado aceptado")
	}
	if _, err = Replay(plan, []Action{{ID: 4, At: 1}}); err == nil {
		t.Fatal("clic antes de aparecer")
	}
	if _, err = Replay(plan, []Action{{ID: 0, At: plan.Drops[0].Until}}); err == nil {
		t.Fatal("clic después de perder ingrediente")
	}
	empty, _ := Replay(plan, nil)
	if empty.Score != 0 || empty.Coins != 0 || empty.Lost == 0 {
		t.Fatalf("partida sin jugar %+v", empty)
	}
	// Also supply a cross-language fixture to Godot when explicitly requested.
	if path := os.Getenv("COFFEE_FIXTURE_PATH"); path != "" {
		data, _ := json.Marshal(map[string]any{"plan": plan, "actions": actions, "expected": result})
		if err = os.WriteFile(path, data, 0644); err != nil {
			t.Fatal(err)
		}
	}
}
func TestMissesAndLevels(t *testing.T) {
	plan, _ := NewPlan()
	e := NewEngine(plan)
	e.Score = 100
	e.Advance(plan.Drops[0].Until)
	if e.Score != 60 || e.Lost != 2 {
		t.Fatalf("solo café y leche necesarios deben penalizar: %+v", e.Result())
	}
	for level, speed := range Speeds {
		at := level * 15000
		if Level(at) != level+1 || Distance(at+1000)-Distance(at) != speed*1000 {
			t.Fatal("nivel/velocidad incorrectos")
		}
	}
	for _, drop := range plan.Drops {
		if Distance(drop.Until)-Distance(drop.At) < Travel || Distance(drop.Until-1)-Distance(drop.At) >= Travel {
			t.Fatal("caducidad no coincide con caída")
		}
	}
}
