package main

import (
	"context"
	"database/sql"
	_ "embed"
)

//go:embed migrations/001_accounts.sql
var accountsMigration string

//go:embed migrations/002_coffee_runs.sql
var coffeeMigration string

func applyMigrations(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, accountsMigration+"\n"+coffeeMigration)
	return err
}
