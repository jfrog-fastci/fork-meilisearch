# Chef base with cargo-chef pre-installed (Debian-based for better build performance vs Alpine/musl)
FROM    lukemathwalker/cargo-chef:latest-rust-1-slim-bookworm AS chef
WORKDIR /app
RUN     apt-get update && apt-get install -y --no-install-recommends libssl-dev pkg-config && \
        rm -rf /var/lib/apt/lists/*

# Plan: Analyze dependencies and generate a recipe.
# The recipe only changes when Cargo.toml/Cargo.lock change, not on source edits.
FROM    chef AS planner
COPY    . .
RUN     cargo chef prepare --recipe-path recipe.json

# Build: Cook dependencies (cached), then compile source
FROM    chef AS builder

COPY    --from=planner /app/recipe.json recipe.json
RUN     cargo chef cook --release --recipe-path recipe.json

ARG     COMMIT_SHA
ARG     COMMIT_DATE
ARG     GIT_TAG
ARG     EXTRA_ARGS
ENV     VERGEN_GIT_SHA=${COMMIT_SHA} VERGEN_GIT_COMMIT_TIMESTAMP=${COMMIT_DATE} VERGEN_GIT_DESCRIBE=${GIT_TAG}

COPY    . .
RUN     set -eux; \
        cargo build --release -p meilisearch -p meilitool ${EXTRA_ARGS}

# Run
FROM    debian:bookworm-slim
LABEL   org.opencontainers.image.source="https://github.com/meilisearch/meilisearch"

ENV     MEILI_HTTP_ADDR 0.0.0.0:7700
ENV     MEILI_SERVER_PROVIDER docker

RUN     apt-get update && \
        apt-get install -y --no-install-recommends tini curl ca-certificates libgcc-s1 libssl3 && \
        rm -rf /var/lib/apt/lists/*

# add meilisearch and meilitool to the `/bin` so you can run it from anywhere
# and it's easy to find.
COPY    --from=builder /app/target/release/meilisearch /bin/meilisearch
COPY    --from=builder /app/target/release/meilitool /bin/meilitool
# To stay compatible with the older version of the container (pre v0.27.0) we're
# going to symlink the meilisearch binary in the path to `/meilisearch`
RUN     ln -s /bin/meilisearch /meilisearch

# This directory should hold all the data related to meilisearch so we're going
# to move our PWD in there.
WORKDIR /meili_data


EXPOSE  7700/tcp

ENTRYPOINT ["tini", "--"]
CMD     /bin/meilisearch
