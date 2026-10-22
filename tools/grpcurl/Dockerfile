FROM golang:1.26-alpine AS build
RUN CGO_ENABLED=0 go install github.com/fullstorydev/grpcurl/cmd/grpcurl@v1.9.4
FROM alpine:3.21
RUN adduser -D app
COPY --from=build /go/bin/grpcurl /usr/local/bin/grpcurl
USER app
ENTRYPOINT ["grpcurl"]
