# ---- build stage ----
FROM golang:1.25.0-alpine3.22 AS builder
WORKDIR /src
RUN apk add --no-cache git ca-certificates
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /out/simple-go-service ./cmd/simple-go-service

# ---- run stage ----
FROM gcr.io/distroless/static:nonroot
USER nonroot:nonroot
WORKDIR /app
COPY --from=builder /out/simple-go-service /app/simple-go-service
EXPOSE 8080
ENTRYPOINT ["/app/simple-go-service"]
