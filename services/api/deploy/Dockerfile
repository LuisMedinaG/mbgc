FROM golang:1.25-alpine AS builder
WORKDIR /app

# Copy shared library and service source
COPY pkg/shared ./pkg/shared
COPY services/api ./services/api

# Build from repo root so go.work resolves pkg/shared locally
COPY go.work go.work.sum ./
WORKDIR /app/services/api
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
