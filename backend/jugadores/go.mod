module jugadores

go 1.26.0

require github.com/lib/pq v1.10.9

require (
	google.golang.org/grpc v1.84.0
	pixelpenguin/platform v0.0.0
)

require (
	golang.org/x/net v0.60.0 // indirect
	golang.org/x/sys v0.49.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260706201446-f0a921348800 // indirect
	google.golang.org/protobuf v1.36.12 // indirect
)

replace pixelpenguin/platform => ../../platform

require (
	golang.org/x/crypto v0.58.0
	golang.org/x/text v0.43.0
)
