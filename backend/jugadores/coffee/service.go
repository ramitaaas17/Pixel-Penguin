package coffee

import (
	"context"
	"database/sql"
	"encoding/json"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"pixelpenguin/platform/coffeegame"
	"pixelpenguin/platform/rpcutil"
	"time"
)

type Service struct {
	DB  *sql.DB
	Now func() time.Time
}

func New(db *sql.DB) *Service { return &Service{DB: db, Now: time.Now} }
func (s *Service) Start(ctx context.Context, playerID int64) (coffeegame.Plan, error) {
	plan, err := coffeegame.NewPlan()
	if err != nil {
		return plan, status.Error(codes.Internal, "No se pudo preparar la partida")
	}
	payload, err := json.Marshal(plan)
	if err != nil {
		return plan, err
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return plan, rpcutil.DatabaseError(err)
	}
	defer tx.Rollback()
	var id int64
	if err = tx.QueryRowContext(ctx, "SELECT id FROM jugadores WHERE id=$1 FOR UPDATE", playerID).Scan(&id); err != nil {
		return plan, rpcutil.DatabaseError(err)
	}
	if _, err = tx.ExecContext(ctx, "UPDATE coffee_runs SET state='abandoned' WHERE player_id=$1 AND state='playing'", playerID); err != nil {
		return plan, rpcutil.DatabaseError(err)
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO coffee_runs(id,player_id,plan,started_at) VALUES($1,$2,$3,$4)", plan.ID, playerID, string(payload), s.Now()); err != nil {
		return plan, rpcutil.DatabaseError(err)
	}
	if err = tx.Commit(); err != nil {
		return plan, rpcutil.DatabaseError(err)
	}
	return plan, nil
}
func (s *Service) Finish(ctx context.Context, playerID int64, id string, actions []coffeegame.Action) (coffeegame.Result, error) {
	var result coffeegame.Result
	if len(id) != 32 || len(actions) > 128 {
		return result, status.Error(codes.InvalidArgument, "Partida inválida")
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	defer tx.Rollback()
	var balance int64
	if err = tx.QueryRowContext(ctx, "SELECT monedas FROM jugadores WHERE id=$1 FOR UPDATE", playerID).Scan(&balance); err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	var payload, saved []byte
	var started time.Time
	var state string
	err = tx.QueryRowContext(ctx, "SELECT plan,result,started_at,state FROM coffee_runs WHERE id=$1 AND player_id=$2 FOR UPDATE", id, playerID).Scan(&payload, &saved, &started, &state)
	if err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	if state == "claimed" {
		if err = json.Unmarshal(saved, &result); err != nil {
			return result, status.Error(codes.Internal, "Resultado guardado inválido")
		}
		result.Balance = balance
		return result, nil
	}
	if state != "playing" {
		return result, status.Error(codes.FailedPrecondition, "Esta partida ya no está activa")
	}
	elapsed := s.Now().Sub(started)
	if elapsed < time.Minute {
		return result, status.Error(codes.FailedPrecondition, "El turno todavía no termina")
	}
	if elapsed > 10*time.Minute {
		return result, status.Error(codes.FailedPrecondition, "La partida expiró")
	}
	var plan coffeegame.Plan
	if err = json.Unmarshal(payload, &plan); err != nil {
		return result, status.Error(codes.Internal, "Partida guardada inválida")
	}
	result, err = coffeegame.Replay(plan, actions)
	if err != nil {
		return result, status.Error(codes.InvalidArgument, "Las acciones no corresponden a la partida")
	}
	if err = tx.QueryRowContext(ctx, "UPDATE jugadores SET monedas=monedas+$1 WHERE id=$2 AND monedas <= 2147483647-$1 RETURNING monedas", result.Coins, playerID).Scan(&result.Balance); err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	saved, err = json.Marshal(result)
	if err != nil {
		return result, err
	}
	if _, err = tx.ExecContext(ctx, "UPDATE coffee_runs SET state='claimed',result=$1,claimed_at=$2 WHERE id=$3", string(saved), s.Now(), id); err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	if err = tx.Commit(); err != nil {
		return result, rpcutil.DatabaseError(err)
	}
	return result, nil
}
