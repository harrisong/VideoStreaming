FROM rust:1.88

# Install dependencies
RUN apt-get update && apt-get install -y ca-certificates libssl-dev python3 python3-pip python3-venv && rm -rf /var/lib/apt/lists/*

# Create a virtual environment and install yt-dlp
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install yt-dlp

WORKDIR /usr/src/app
COPY . .
RUN cargo update
RUN cargo build --release
RUN cp target/release/youtube_scraper /usr/local/bin/youtube_scraper

# Create a directory for temporary video downloads
RUN mkdir -p /tmp/videos

WORKDIR /usr/src/app

# Make the entrypoint script executable
RUN chmod +x docker-entrypoint.sh

# Use our entrypoint script
ENTRYPOINT ["./docker-entrypoint.sh"]
