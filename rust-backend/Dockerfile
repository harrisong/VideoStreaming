FROM rust:1.88 as builder
WORKDIR /usr/src/video_streaming_backend
COPY ./.sqlx ./.sqlx
COPY ./src ./src
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml
COPY ./target ./target
RUN cargo sqlx prepare
RUN cargo update
ENV SQLX_OFFLINE=true
ARG DATABASE_URL
ENV DATABASE_URL=$DATABASE_URL
RUN cargo build --release

FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y libpq-dev ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/src/video_streaming_backend/target/release/video_streaming_backend /usr/local/bin/video_streaming_backend
ENV RUST_LOG=info
EXPOSE 5050
CMD ["video_streaming_backend"]
