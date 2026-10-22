package auth

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/text/unicode/norm"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	pb "pixelpenguin/platform/gen/penguin/v1"
	"pixelpenguin/platform/rpcutil"
	"pixelpenguin/platform/session"
	"strings"
	"time"
	"unicode/utf8"
)

type Service struct {
	pb.UnimplementedAuthServer
	store     Store
	dummyHash []byte
	work      chan struct{}
}

func New(store Store) (*Service, error) {
	dummy := make([]byte, 32)
	if _, err := rand.Read(dummy); err != nil {
		return nil, err
	}
	hash, err := bcrypt.GenerateFromPassword(dummy, 12)
	if err != nil {
		return nil, err
	}
	return &Service{store: store, dummyHash: hash, work: make(chan struct{}, 4)}, nil
}
func usernameKey(value string) (string, string, bool) {
	value = norm.NFC.String(strings.TrimSpace(value))
	if count := utf8.RuneCountInString(value); count < 3 || count > 20 {
		return "", "", false
	}
	for _, character := range value {
		if !((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || strings.ContainsRune("áéíóúÁÉÍÓÚüÜñÑ_", character)) {
			return "", "", false
		}
	}
	return value, strings.ToLower(value), true
}
func (service *Service) acquire() (func(), error) {
	select {
	case service.work <- struct{}{}:
		return func() { <-service.work }, nil
	default:
		return nil, status.Error(codes.ResourceExhausted, "Hay varias solicitudes. Intenta de nuevo en un momento")
	}
}
func newToken() (string, []byte, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, status.Error(codes.Internal, "No se pudo iniciar la sesión")
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	hash, err := session.Hash(token)
	return token, hash, err
}
func response(identity *Identity, token string) *pb.Session {
	return &pb.Session{Token: token, ExpiresAt: identity.ExpiresAt.Unix(), Player: &pb.Player{Id: int64(identity.Player.Id), Name: identity.Player.Nombre, Coins: int64(identity.Player.Monedas)}}
}
func (service *Service) Register(ctx context.Context, request *pb.Credentials) (*pb.Session, error) {
	username, key, valid := usernameKey(request.Username)
	if !valid {
		return nil, status.Error(codes.InvalidArgument, "Usa de 3 a 20 letras en español, números o guion bajo")
	}
	if utf8.RuneCountInString(request.Password) < 8 || len(request.Password) > 72 || !utf8.ValidString(request.Password) {
		return nil, status.Error(codes.InvalidArgument, "Usa al menos 8 caracteres y un máximo de 72 bytes")
	}
	release, err := service.acquire()
	if err != nil {
		return nil, err
	}
	defer release()
	hash, err := bcrypt.GenerateFromPassword([]byte(request.Password), 12)
	if err != nil {
		return nil, status.Error(codes.Internal, "No se pudo crear la cuenta")
	}
	if err = ctx.Err(); err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	token, tokenHash, err := newToken()
	if err != nil {
		return nil, err
	}
	identity, err := service.store.Register(ctx, username, key, string(hash), tokenHash, time.Now().Add(12*time.Hour))
	if err != nil {
		var databaseError *pq.Error
		if errors.As(err, &databaseError) && databaseError.Code == "23505" {
			return nil, status.Error(codes.AlreadyExists, "Ese nombre de usuario ya está ocupado")
		}
		return nil, rpcutil.DatabaseError(err)
	}
	return response(identity, token), nil
}
func (service *Service) Login(ctx context.Context, request *pb.Credentials) (*pb.Session, error) {
	_, key, valid := usernameKey(request.Username)
	if !valid || len(request.Password) > 72 {
		return nil, status.Error(codes.Unauthenticated, "Usuario o contraseña incorrectos")
	}
	release, err := service.acquire()
	if err != nil {
		return nil, err
	}
	defer release()
	account, lookupError := service.store.FindAccount(ctx, key)
	if lookupError != nil && !errors.Is(lookupError, sql.ErrNoRows) {
		return nil, rpcutil.DatabaseError(lookupError)
	}
	hash := service.dummyHash
	if lookupError == nil {
		hash = []byte(account.PasswordHash)
	}
	compareError := bcrypt.CompareHashAndPassword(hash, []byte(request.Password))
	if compareError != nil || lookupError != nil {
		return nil, status.Error(codes.Unauthenticated, "Usuario o contraseña incorrectos")
	}
	token, tokenHash, err := newToken()
	if err != nil {
		return nil, err
	}
	identity, err := service.store.CreateSession(ctx, account.ID, tokenHash, time.Now().Add(12*time.Hour))
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	return response(identity, token), nil
}
func (service *Service) GetSession(ctx context.Context, request *pb.Empty) (*pb.Session, error) {
	token, err := session.Token(ctx)
	if err != nil {
		return nil, err
	}
	hash, _ := session.Hash(token)
	identity, err := service.store.FindSession(ctx, hash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, status.Error(codes.Unauthenticated, "Tu sesión terminó. Vuelve a entrar")
	}
	if err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	return response(identity, ""), nil
}
func (service *Service) Logout(ctx context.Context, request *pb.Empty) (*pb.Empty, error) {
	token, err := session.Token(ctx)
	if err != nil {
		return nil, err
	}
	hash, _ := session.Hash(token)
	if err = service.store.Revoke(ctx, hash); err != nil {
		return nil, rpcutil.DatabaseError(err)
	}
	return &pb.Empty{}, nil
}
