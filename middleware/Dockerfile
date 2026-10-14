FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
COPY main.go ./
COPY services.json ./
RUN go mod tidy
RUN go build -o middleware .

FROM alpine:latest
WORKDIR /app
COPY --from=build /app/middleware .
COPY --from=build /app/services.json .
EXPOSE 8000
CMD ["./middleware"]
