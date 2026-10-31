// Package coffeegame replays a server-issued coffee game without trusting scores.
package coffeegame

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sort"
)

const Duration = 60000
const Travel = 338000 // 338 pixels, in thousandths; arena is 448 logical pixels tall.
var Recipes = [][4]int{{3, 2, 0, 0}, {0, 2, 3, 1}, {2, 2, 2, 0}, {3, 1, 0, 2}, {0, 2, 4, 0}}
var Speeds = []int{42, 56, 70, 86}

type Drop struct {
	ID    int `json:"id"`
	Kind  int `json:"kind"`
	At    int `json:"at_ms"`
	Until int `json:"until_ms"`
}
type Plan struct {
	ID       string `json:"run_id"`
	Duration int    `json:"duration_ms"`
	Recipes  []int  `json:"recipes"`
	Drops    []Drop `json:"drops"`
}
type Action struct {
	ID int `json:"drop_id"`
	At int `json:"at_ms"`
}
type Result struct {
	Score   int   `json:"score"`
	Coins   int   `json:"coins"`
	Balance int64 `json:"balance"`
	Served  int   `json:"served"`
	Lost    int   `json:"lost"`
	Wrong   int   `json:"wrong"`
	Level   int   `json:"level"`
}

func Level(at int) int { return min(4, at/15000+1) }
func Distance(at int) int {
	total := 0
	for i, speed := range Speeds {
		span := max(0, min(15000, at-i*15000))
		if i == 3 {
			span = max(0, at-i*15000)
		}
		total += span * speed
	}
	return total
}
func expiry(at int) int {
	target := Distance(at) + Travel
	for level, speed := range Speeds {
		base := Distance(level * 15000)
		end := Distance((level + 1) * 15000)
		if target <= end || level == 3 {
			return level*15000 + (target-base+speed-1)/speed
		}
	}
	panic("unreachable")
}
func NewPlan() (Plan, error) {
	var random [128]byte
	if _, err := rand.Read(random[:]); err != nil {
		return Plan{}, err
	}
	plan := Plan{ID: hex.EncodeToString(random[:16]), Duration: Duration, Recipes: []int{0}}
	for i := 1; i < 64; i++ {
		next := int(random[16+i]) % 4
		if next >= plan.Recipes[i-1] {
			next++
		}
		plan.Recipes = append(plan.Recipes, next)
	}
	for i := 0; ; i++ {
		at := 0
		if i >= 4 {
			at = (i) * 650
		}
		if at >= Duration {
			break
		}
		plan.Drops = append(plan.Drops, Drop{ID: i, Kind: i % 4, At: at, Until: expiry(at)})
	}
	return plan, nil
}

type Engine struct {
	Plan                                              Plan
	Score, Served, Lost, Wrong, Combo, MissedOrders   int
	Collected                                         [4]int
	RecipePosition, Recipe, Clock, Deadline, Cooldown int
	expired                                           int
	expirations                                       []Drop
	clicked                                           map[int]bool
	drops                                             map[int]Drop
}

func NewEngine(plan Plan) *Engine {
	e := &Engine{Plan: plan, Recipe: plan.Recipes[0], Deadline: 24000, clicked: map[int]bool{}, drops: map[int]Drop{}, expirations: append([]Drop{}, plan.Drops...)}
	for _, drop := range plan.Drops {
		e.drops[drop.ID] = drop
	}
	sort.Slice(e.expirations, func(i, j int) bool {
		a, b := e.expirations[i], e.expirations[j]
		if a.Until == b.Until {
			return a.ID < b.ID
		}
		return a.Until < b.Until
	})
	return e
}
func (e *Engine) nextOrder() {
	e.RecipePosition++
	e.Recipe = e.Plan.Recipes[e.RecipePosition%len(e.Plan.Recipes)]
	e.Collected = [4]int{}
	e.Deadline = e.Clock + 24000
	e.Cooldown = 0
}
func (e *Engine) Advance(to int) {
	to = min(Duration, max(to, e.Clock))
	for {
		next := Duration + 1
		if e.Cooldown > 0 {
			next = e.Cooldown
		} else {
			next = e.Deadline
		}
		if e.expired < len(e.expirations) {
			next = min(next, e.expirations[e.expired].Until)
		}
		if next > to {
			break
		}
		e.Clock = next
		if e.Cooldown > 0 && next == e.Cooldown {
			e.nextOrder()
		}
		if e.Cooldown == 0 && next == e.Deadline {
			e.MissedOrders++
			e.Combo = 0
			e.nextOrder()
		}
		for e.expired < len(e.expirations) && e.expirations[e.expired].Until == next {
			drop := e.expirations[e.expired]
			e.expired++
			if !e.clicked[drop.ID] && e.Cooldown == 0 && e.Collected[drop.Kind] < Recipes[e.Recipe][drop.Kind] {
				e.Score = max(0, e.Score-20)
				e.Lost++
				e.Combo = 0
			}
		}
	}
	e.Clock = to
}
func (e *Engine) Click(action Action) error {
	if action.At < e.Clock || action.At < 0 || action.At >= Duration {
		return fmt.Errorf("tiempo de clic inválido")
	}
	e.Advance(action.At)
	drop, ok := e.drops[action.ID]
	if !ok || e.clicked[action.ID] || action.At < drop.At || action.At >= drop.Until || e.Cooldown > 0 {
		return fmt.Errorf("ingrediente no disponible")
	}
	e.clicked[action.ID] = true
	needed := Recipes[e.Recipe]
	if e.Collected[drop.Kind] >= needed[drop.Kind] {
		if needed[drop.Kind] == 0 {
			e.Score = max(0, e.Score-10)
			e.Wrong++
			e.Combo = 0
		}
		return nil
	}
	e.Collected[drop.Kind]++
	if e.Collected == needed {
		e.Combo++
		e.Served++
		e.Score += 100 + (Level(e.Clock)-1)*25 + min(e.Combo-1, 5)*25 + max(0, e.Deadline-e.Clock)/1000*2
		e.Cooldown = e.Clock + 900
	}
	return nil
}
func (e *Engine) Result() Result {
	return Result{Score: e.Score, Coins: min(50, e.Score/100), Served: e.Served, Lost: e.Lost, Wrong: e.Wrong, Level: Level(e.Clock)}
}
func Replay(plan Plan, actions []Action) (Result, error) {
	if len(actions) > len(plan.Drops) {
		return Result{}, fmt.Errorf("demasiados clics")
	}
	e := NewEngine(plan)
	for _, action := range actions {
		if err := e.Click(action); err != nil {
			return Result{}, err
		}
	}
	e.Advance(Duration)
	return e.Result(), nil
}
