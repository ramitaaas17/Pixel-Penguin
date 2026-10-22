package auth

import (
	"context"
	"database/sql"
	"jugadores/models"
	"time"
)

type Account struct {
	ID           int
	PasswordHash string
}
type Identity struct {
	Player    models.Jugador
	ExpiresAt time.Time
}
type Store interface {
	Register(context.Context, string, string, string, []byte, time.Time) (*Identity, error)
	FindAccount(context.Context, string) (*Account, error)
	CreateSession(context.Context, int, []byte, time.Time) (*Identity, error)
	FindSession(context.Context, []byte) (*Identity, error)
	Revoke(context.Context, []byte) error
}
type Repository struct{ db *sql.DB }

func NewRepository(db *sql.DB) *Repository { return &Repository{db: db} }
func (repository *Repository) Register(ctx context.Context, username, key, passwordHash string, tokenHash []byte, expiresAt time.Time) (*Identity, error) {
	tx, err := repository.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	identity := &Identity{ExpiresAt: expiresAt}
	err = tx.QueryRowContext(ctx, "INSERT INTO jugadores(nombre,monedas) VALUES($1,100) RETURNING id,nombre,monedas", username).Scan(&identity.Player.Id, &identity.Player.Nombre, &identity.Player.Monedas)
	if err != nil {
		return nil, err
	}
	var accountID int
	err = tx.QueryRowContext(ctx, "INSERT INTO accounts(username,username_key,password_hash,player_id) VALUES($1,$2,$3,$4) RETURNING id", username, key, passwordHash, identity.Player.Id).Scan(&accountID)
	if err != nil {
		return nil, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO sessions(token_hash,account_id,expires_at) VALUES($1,$2,$3)", tokenHash, accountID, expiresAt); err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return identity, nil
}
func (repository *Repository) FindAccount(ctx context.Context, key string) (*Account, error) {
	account := &Account{}
	err := repository.db.QueryRowContext(ctx, "SELECT id,password_hash FROM accounts WHERE username_key=$1", key).Scan(&account.ID, &account.PasswordHash)
	return account, err
}
func (repository *Repository) CreateSession(ctx context.Context, accountID int, tokenHash []byte, expiresAt time.Time) (*Identity, error) {
	tx, err := repository.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "DELETE FROM sessions WHERE expires_at <= NOW()"); err != nil {
		return nil, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO sessions(token_hash,account_id,expires_at) VALUES($1,$2,$3)", tokenHash, accountID, expiresAt); err != nil {
		return nil, err
	}
	identity := &Identity{ExpiresAt: expiresAt}
	err = tx.QueryRowContext(ctx, "SELECT j.id,j.nombre,j.monedas FROM accounts a JOIN jugadores j ON j.id=a.player_id WHERE a.id=$1", accountID).Scan(&identity.Player.Id, &identity.Player.Nombre, &identity.Player.Monedas)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return identity, nil
}
func (repository *Repository) FindSession(ctx context.Context, tokenHash []byte) (*Identity, error) {
	identity := &Identity{}
	err := repository.db.QueryRowContext(ctx, "SELECT j.id,j.nombre,j.monedas,s.expires_at FROM sessions s JOIN accounts a ON a.id=s.account_id JOIN jugadores j ON j.id=a.player_id WHERE s.token_hash=$1 AND s.expires_at>NOW()", tokenHash).Scan(&identity.Player.Id, &identity.Player.Nombre, &identity.Player.Monedas, &identity.ExpiresAt)
	return identity, err
}
func (repository *Repository) Revoke(ctx context.Context, tokenHash []byte) error {
	_, err := repository.db.ExecContext(ctx, "DELETE FROM sessions WHERE token_hash=$1", tokenHash)
	return err
}
