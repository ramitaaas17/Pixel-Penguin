package rpcutil

import (
	"context"
	"database/sql"
	"errors"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"strings"
	"testing"
)

func TestDatabaseErrorsAreSafeAndPreserveCancellation(t *testing.T) {
	for _, testCase := range []struct {
		err  error
		code codes.Code
	}{
		{sql.ErrNoRows, codes.NotFound}, {context.Canceled, codes.Canceled}, {context.DeadlineExceeded, codes.DeadlineExceeded}, {errors.New("secret SQL detail"), codes.Internal},
	} {
		result := DatabaseError(testCase.err)
		if status.Code(result) != testCase.code || strings.Contains(result.Error(), "secret") {
			t.Fatalf("unsafe or incorrect error: %v", result)
		}
	}
}
