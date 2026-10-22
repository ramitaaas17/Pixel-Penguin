package auth

import (
	"bytes"
	"context"
	"database/sql"
	"github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"jugadores/models"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"testing"
	"time"
)

type memoryStore struct {
	passwordHash, key string
	tokenHash         []byte
	identity          *Identity
	registerError     error
}

func (store *memoryStore) Register(ctx context.Context, name, key, hash string, tokenHash []byte, expiry time.Time) (*Identity, error) {
	if store.registerError != nil {
		return nil, store.registerError
	}
	store.passwordHash, store.key, store.tokenHash = hash, key, tokenHash
	store.identity = &Identity{Player: models.Jugador{Id: 17, Nombre: name, Monedas: 100}, ExpiresAt: expiry}
	return store.identity, nil
}
func (store *memoryStore) FindAccount(ctx context.Context, key string) (*Account, error) {
	if store.key != key {
		return nil, sql.ErrNoRows
	}
	return &Account{ID: 1, PasswordHash: store.passwordHash}, nil
}
func (store *memoryStore) CreateSession(ctx context.Context, id int, hash []byte, expiry time.Time) (*Identity, error) {
	store.tokenHash = hash
	store.identity.ExpiresAt = expiry
	return store.identity, nil
}
func (store *memoryStore) FindSession(ctx context.Context, hash []byte) (*Identity, error) {
	if !bytes.Equal(hash, store.tokenHash) {
		return nil, sql.ErrNoRows
	}
	return store.identity, nil
}
func (store *memoryStore) Revoke(ctx context.Context, hash []byte) error {
	store.tokenHash = nil
	return nil
}
func TestAccountSessionLifecycle(t *testing.T) {
	store := &memoryStore{}
	service, err := New(store)
	if err != nil {
		t.Fatal(err)
	}
	registered, err := service.Register(context.Background(), &pb.Credentials{Username: "Ñandu\u0301", Password: "Invierno123!"})
	if err != nil {
		t.Fatal(err)
	}
	if store.key != "ñandú" || registered.Player.Name != "Ñandú" || registered.Player.Coins != 100 {
		t.Fatal("identity not normalized")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(store.passwordHash), []byte("Invierno123!")); err != nil {
		t.Fatal(err)
	}
	if len(registered.Token) != 43 || bytes.Contains(store.tokenHash, []byte(registered.Token)) {
		t.Fatal("invalid token storage")
	}
	ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs("authorization", "Bearer "+registered.Token))
	validated, err := service.GetSession(ctx, &pb.Empty{})
	if err != nil || validated.Player.Id != 17 || validated.Token != "" {
		t.Fatal("invalid session", err)
	}
	if _, err := service.Logout(ctx, &pb.Empty{}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.GetSession(ctx, &pb.Empty{}); status.Code(err) != codes.Unauthenticated {
		t.Fatal("revoked session accepted", err)
	}
	for _, credentials := range []*pb.Credentials{{Username: "ÑANDÚ", Password: "wrong-password"}, {Username: "missing", Password: "wrong-password"}} {
		if _, err := service.Login(context.Background(), credentials); status.Code(err) != codes.Unauthenticated {
			t.Fatal(err)
		}
	}
	if _, err := service.Login(context.Background(), &pb.Credentials{Username: "ÑANDÚ", Password: "Invierno123!"}); err != nil {
		t.Fatal(err)
	}
	store.registerError = &pq.Error{Code: "23505"}
	if _, err := service.Register(context.Background(), &pb.Credentials{Username: "Ñandú", Password: "Invierno123!"}); status.Code(err) != codes.AlreadyExists {
		t.Fatal(err)
	}
}
func TestCredentialValidation(t *testing.T) {
	store := &memoryStore{}
	service, err := New(store)
	if err != nil {
		t.Fatal(err)
	}
	for _, credentials := range []*pb.Credentials{{Username: "a", Password: "Invierno123!"}, {Username: "name", Password: "short"}, {Username: "bad name", Password: "Invierno123!"}} {
		if _, err := service.Register(context.Background(), credentials); status.Code(err) != codes.InvalidArgument {
			t.Fatal(err)
		}
	}
}
