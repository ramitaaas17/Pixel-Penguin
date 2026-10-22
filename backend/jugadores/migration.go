package main

import (
	"context"
	"database/sql"
	_ "embed"
)

//go:embed migrations/001_accounts.sql
var accountsMigration string

func applyMigrations(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, accountsMigration)
	return err
}
