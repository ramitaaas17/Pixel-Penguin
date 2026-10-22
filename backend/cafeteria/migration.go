package main

import (
	"context"
	"database/sql"
	_ "embed"
)

//go:embed migrations/001_order_player.sql
var orderPlayerMigration string

func applyMigrations(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, orderPlayerMigration)
	return err
}
