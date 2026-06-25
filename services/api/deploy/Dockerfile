FROM golang:1.26-alpine AS builder
WORKDIR /app

# Copy service source (internal packages moved under services/api/internal/)
COPY services/api ./services/api

# Build from repo root so go.work resolves modules locally.
COPY go.mod go.work go.work.sum ./
WORKDIR /app/services/api
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
