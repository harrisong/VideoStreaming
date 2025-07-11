FROM rust:1.88

# Install dependencies
RUN apt-get update && apt-get install -y ca-certificates libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
COPY . .
RUN cargo update
RUN cargo build --release
RUN cp target/release/youtube_scraper /usr/local/bin/youtube_scraper

# Create a directory for temporary video downloads
RUN mkdir -p /tmp/videos

WORKDIR /tmp/videos

# Run in server mode by default
CMD ["youtube_scraper", "--server"]
