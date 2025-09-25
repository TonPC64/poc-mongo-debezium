# Development Dockerfile with Air for hot reload
FROM golang:1.24-alpine

# Install dependencies and Air for hot reload
RUN apk add --no-cache curl && \
    curl -sSfL https://raw.githubusercontent.com/cosmtrek/air/master/install.sh | sh -s -- -b $(go env GOPATH)/bin

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Create tmp directory for Air
RUN mkdir -p tmp

# Expose port if needed
EXPOSE 8080

# Use Air for hot reload
CMD ["air", "-c", ".air.toml"]