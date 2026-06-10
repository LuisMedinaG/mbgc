FROM golang:1.25-alpine AS builder
WORKDIR /app

# Copy shared library and service source
COPY pkg/shared ./pkg/shared
COPY services/api ./services/api

# Build from repo root so go.work resolves pkg/shared locally.
# go.work's `use .` requires the workspace root to be a module — must
# COPY go.mod from the repo root, not just go.work / go.work.sum.
COPY go.mod go.work go.work.sum ./
WORKDIR /app/services/api
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
