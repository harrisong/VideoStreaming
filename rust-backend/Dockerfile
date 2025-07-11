FROM rust:1.88

# Install dependencies
RUN apt-get update && apt-get install -y libpq-dev ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/video_streaming_backend
COPY . .
RUN cargo update
RUN cargo build --release
RUN cp target/release/video_streaming_backend /usr/local/bin/video_streaming_backend
ENV RUST_LOG=info
EXPOSE 5050
EXPOSE 8080
CMD ["video_streaming_backend"]
