FROM golang:1.26-alpine AS build
WORKDIR /src
COPY platform/go.mod platform/go.sum ./platform/
COPY platform/gen ./platform/gen
COPY platform/rpcutil ./platform/rpcutil
COPY platform/session ./platform/session
COPY platform/registry ./platform/registry
COPY platform/messaging ./platform/messaging
COPY platform/coffeegame ./platform/coffeegame
WORKDIR /src/backend/jugadores
COPY backend/jugadores/go.mod backend/jugadores/go.sum ./
RUN go mod download
COPY backend/jugadores/ .
RUN CGO_ENABLED=0 go build -trimpath -o /service .
FROM alpine:3.21
RUN adduser -D app
COPY --from=build /service /usr/local/bin/service
USER app
EXPOSE 8080 9090
CMD ["service"]
