FROM golang:1.26-alpine AS build
WORKDIR /src/platform
COPY platform/go.mod platform/go.sum ./
RUN go mod download
COPY platform/cmd/gateway ./cmd/gateway
RUN CGO_ENABLED=0 go build -trimpath -o /gateway ./cmd/gateway
FROM nginx:1.28-alpine
COPY --from=build /gateway /usr/local/bin/gateway
COPY nginx/nginx.conf.tmpl /etc/nginx/nginx.conf.tmpl
STOPSIGNAL SIGTERM
ENTRYPOINT ["gateway"]
