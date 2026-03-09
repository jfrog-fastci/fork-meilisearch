# FastCI Insight Catalog

Reference for all insight types that FastCI traces can detect as `best_practices.missing`. Read this file when building the improvement plan (Phase 2) and applying remediations (Phase 3).

Each insight lists what it detects and the safety rules for applying it.

---

## Unpinned base image version

**Detects:** Base image uses `latest`, a major-only tag, or a minor-only tag (e.g. `golang:1.25`) instead of a fully pinned version. Floating tags cause unpredictable cache invalidation when the upstream image publishes a new digest.

**How to apply:**
- Read the repo's version files before pinning: `go.mod` (Go), `package.json`/`.nvmrc`/`.node-version` (Node), `pyproject.toml`/`.python-version` (Python), `pom.xml`/`.java-version` (Java).
- Pin to a patch-level release that satisfies the declared version (e.g. `golang:1.25.0`).
- If no explicit version is declared, keep the current major/minor family and pin a stable patch release.
- Keep the distro family compatible with the existing image (e.g. don't switch from `-bookworm` to `-alpine` without cause).

## Inefficient layer ordering / dependency-first copy

**Detects:** Source code is copied before dependency installation, so every code change invalidates the dependency cache layer.

**How to apply:**
- Copy only dependency manifests first (`go.mod`, `go.sum`, `package.json`, `package-lock.json`, etc.), run the install command, then copy the rest of the source.
- Before adding any `COPY` for a manifest or lockfile, verify the file exists in the repo and is within the Docker build context.
- Never add `COPY go.sum` unless `go.sum` exists. Same for `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock*`.
- After reordering layers, verify that later build steps still see every source file they need.

## Go dependency download not separated from build

**Detects:** `go mod download` is not run in its own layer before `go build`, so dependency downloads are repeated on every source change.

**How to apply:**
- Copy `go.mod` (and `go.sum` if it exists) into the working directory, run `go mod download`, then copy the remaining source.
- Verify the paths match the actual module location in the repo.

## Using npm install instead of npm ci

**Detects:** `npm install` is used in the Dockerfile instead of `npm ci`, which is slower and non-deterministic.

**How to apply:**
- Only switch to `npm ci` when `package-lock.json` or `npm-shrinkwrap.json` exists in the repo.
- If the repo uses Yarn, pnpm, or Bun, do not force `npm ci` — use the declared package manager's clean-install equivalent.

## Single-stage build with build tools detected

**Detects:** The Dockerfile uses a single stage that includes compilers, dev-dependencies, and build tools in the final image.

**How to apply:**
- Split into a builder stage and a runtime stage.
- Identify all runtime artifacts (binaries, static assets, config files, certs) and explicitly `COPY --from=builder` them into the runtime stage.
- Preserve `WORKDIR`, `ENV`, `EXPOSE`, `ENTRYPOINT`, and `CMD` in the runtime stage.
- If the app makes network calls, include `ca-certificates` in the runtime image unless the base already provides them.
- Do not assume `scratch` or distroless is safe — use a minimal runtime only when the app's dependencies are fully understood.

## apt update/install in separate RUN statements / missing apt cache cleanup

**Detects:** `apt-get update` and `apt-get install` are in separate `RUN` layers, or the apt cache is not cleaned in the same layer.

**How to apply:**
- Consolidate `apt-get update`, `apt-get install`, and `rm -rf /var/lib/apt/lists/*` into a single `RUN` layer.
- Preserve the exact package list — do not add or remove packages as part of this insight.

## apt-get install without --no-install-recommends

**Detects:** `apt-get install` runs without `--no-install-recommends`, pulling in unnecessary recommended packages that increase image size and build time.

**How to apply:**
- Add `--no-install-recommends` to `apt-get install` invocations.
- If the image relies on implicitly recommended packages and the required set is unclear, skip and flag for manual review.

## Remove apt-get upgrade

**Detects:** `apt-get upgrade` runs during the build, which is slow and non-deterministic. Pinning the base image version is the preferred approach.

**How to apply:**
- Remove the `apt-get upgrade` line.
- Only skip removal if the Dockerfile has a documented reason for the upgrade.

## ARG before dependency install invalidates cache

**Detects:** An `ARG` instruction is placed before dependency install layers, causing cache invalidation whenever the build arg changes.

**How to apply:**
- Move the `ARG` below layers that do not reference it and above the first layer that does.
- Trace where each `ARG` is actually used before moving it — never move an `ARG` below a step that depends on it.

## No remote cache configured

**Detects:** The Docker build does not use a remote cache backend, so every CI run builds from scratch.

**How to apply:**
- Verify the workflow uses Docker Buildx before adding cache flags.
- Add `--cache-from type=gha --cache-to type=gha,mode=max` to the `docker buildx build` command.
- If the workflow uses plain `docker build`, add Buildx setup first or skip this insight.
- Keep cache flags aligned with the existing build command's platform flags and output mode.

## Consider using --push flag

**Detects:** The build produces a local image that could be pushed directly using `--push` instead of a separate `docker push` step.

**How to apply:**
- Only apply when the workflow already authenticates to a registry or tags the image for a registry destination.
- If there is no login step, registry hostname, or deployment flow, skip this insight.

## Rust build in docker

**Detects:** The docker build builds rust project without layer caching and/or without dependency caching

**How to apply:**
- Install cargo-chef in the Dockerfile's base image - **DONT** add cargo fetch or other utilities:
  ```dockerfile
  RUN cargo install cargo-chef
  ```
- Create a recipe file in a separate stage:
  ```dockerfile
  FROM rust:1.89-alpine3.22 AS chef
  RUN cargo install cargo-chef
  WORKDIR /app

  FROM chef AS planner
  COPY ./Cargo.toml ./Cargo.lock ./
  # Generate a recipe file for dependencies
  RUN cargo chef prepare --recipe-path recipe.json

  FROM chef AS builder
  COPY --from=planner /app/recipe.json recipe.json
  # Build dependencies only (this layer will be cached)
  RUN cargo chef cook --release --recipe-path recipe.json
  # Now copy source code
  COPY . .
  # Build the application
  RUN cargo build --release
  ```
- In the workflow yaml, add GitHub Actions caching:
  **EXPLICTLY** use cache-to only when github.ref == 'refs/heads/main' in order to avoid
    cache write on feature branches
  ```yaml
  - uses: docker/build-push-action@v6
    with:
      ...
      cache-to: ${{ github.ref == 'refs/heads/main' && 'type=gha,mode=max,scope=<PREFIX>-${{matrix.<PARAMETER_1>}}-${{matrix.<PARAMETER_2>}}...' || '' }}
      cache-from: type=gha,scope=<PREFIX>-${{matrix.<PARAMETER_1>}}-${{matrix.<PARAMETER_2>}}...
      ...
  ```