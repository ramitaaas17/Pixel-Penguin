#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v protoc >/dev/null
mkdir -p .tools/bin platform/gen
export GOBIN="$PWD/.tools/bin"
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.12
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.6.2
export PATH="$GOBIN:$PATH"
protoc -I proto --go_out=platform --go_opt=module=pixelpenguin/platform --go-grpc_out=platform --go-grpc_opt=module=pixelpenguin/platform proto/penguin/v1/*.proto
