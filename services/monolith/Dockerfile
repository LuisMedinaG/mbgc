FROM golang:1.25-alpine AS builder
WORKDIR /app

# Download Tailwind CSS CLI (standalone binary — no Node.js needed)
RUN apk add --no-cache curl && \
    curl -sLo tailwindcss \
      https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64 && \
    chmod +x tailwindcss

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

# Build CSS (minified)
RUN ./tailwindcss -i static/input.css -o static/style.css --minify

# Build Go binary
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

FROM alpine:3.21
RUN apk --no-cache add ca-certificates sqlite
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
