# Build stage
FROM rust:1.88 AS builder

# Install dependencies
RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency files first for better layer caching
COPY Cargo.toml ./

# Create a dummy main.rs to build dependencies (without Cargo.lock for compatibility)
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies (this layer will be cached unless Cargo.toml changes)
RUN cargo build --release && rm -rf src target/release/deps/video_streaming_backend*

# Copy source code (excluding target via .dockerignore)
COPY src ./src
COPY migrations ./migrations
COPY sqlx-data.json ./

# Build the actual application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies including ffprobe
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    libpq5 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/target/release/video_streaming_backend /app/video_streaming_backend

# Copy migrations and init script
COPY --from=builder /app/migrations ./migrations
COPY init-db.sql ./init-db.sql

# Set environment
ENV RUST_LOG=info

# Expose port
EXPOSE 5050

# Run the application
CMD ["./video_streaming_backend"]
