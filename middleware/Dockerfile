FROM golang:1.26-alpine AS build
WORKDIR /src
COPY platform ./platform
WORKDIR /src/middleware
COPY middleware/go.mod middleware/go.sum ./
RUN go mod download
COPY middleware/ .
RUN CGO_ENABLED=0 go build -trimpath -o /application .
FROM alpine:3.21
RUN adduser -D app
COPY --from=build /application /usr/local/bin/application
USER app
EXPOSE 8000
CMD ["application"]
