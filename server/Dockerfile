FROM rust:1-bookworm AS builder
WORKDIR /build

COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/pachat_server* target/release/pachat-server*

COPY src ./src
RUN cargo build --release


FROM debian:bookworm-slim AS runtime
WORKDIR /app

RUN useradd --system --uid 1000 --user-group --no-create-home pachat

COPY --from=builder /build/target/release/pachat-server /usr/local/bin/pachat-server

USER pachat
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/pachat-server"]
CMD ["--host", "0.0.0.0", "--port", "9000"]
