FROM rust:1.70 as builder

WORKDIR /usr/src/app
COPY . .
RUN cargo build --release

FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/app/target/release/youtube_scraper /usr/local/bin/youtube_scraper

# Create a directory for temporary video downloads
RUN mkdir -p /tmp/videos

WORKDIR /tmp/videos

# Run in server mode by default
CMD ["youtube_scraper", "--server"]
