# Offline-ready build for Anthropic OSS Scanner.
# Keep SUI_VERSION in sync with .github/workflows/move_test.yml.
#
# Dash-compatible /bin/sh RUN lines (same style as most enrolled crypto Dockerfiles).
# Network is available only during this build; the scan that follows runs offline.
FROM ubuntu:24.04

ARG TARGETARCH
ARG SUI_VERSION=1.80.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git perl \
    && rm -rf /var/lib/apt/lists/*

# Install the Sui CLI for the build architecture (scanner hosts are x86_64 Linux).
# Stream-extract only `sui` — the release tarball is ~1.1 GB and also ships sui-debug.
# curl -f fails the layer on HTTP errors; a truncated stream makes tar exit non-zero.
RUN arch="$([ "${TARGETARCH:-amd64}" = "arm64" ] && echo aarch64 || echo x86_64)" \
    && mkdir -p /opt/sui \
    && curl -fsSL \
         "https://github.com/MystenLabs/sui/releases/download/mainnet-v${SUI_VERSION}/sui-mainnet-v${SUI_VERSION}-ubuntu-${arch}.tgz" \
       | tar -xz -C /opt/sui sui \
    && chmod +x /opt/sui/sui \
    && /opt/sui/sui --version

ENV PATH="/opt/sui:${PATH}"

# Scanner contract: the checkout lives inside the image at /src.
COPY . /src
WORKDIR /src

# Fetch production dependencies and build (network available during docker build only).
RUN sui move build --lint --path packages/deeptrade-core

# Swap Move.toml to the test-fork pins (same transform as .github/workflows/move_test.yml),
# then fetch those deps and run the suite so the offline agent can re-run tests.
# Do not let a failing test abort the image build.
RUN TOML=packages/deeptrade-core/Move.toml \
    && perl -i -pe 's/^(deepbook = \{ git = "https:\/\/github.com\/MystenLabs\/deepbookv3.git".*\})/# $1/' "$TOML" \
    && perl -i -pe 's/^(token = \{ git = "https:\/\/github.com\/MystenLabs\/deepbookv3.git".*\})/# $1/' "$TOML" \
    && perl -i -pe 's/^(pyth = \{ git = "https:\/\/github.com\/pyth-network\/pyth-crosschain.git".*\})/# $1/' "$TOML" \
    && perl -i -pe 's/^#\s*(deepbook = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/$1/' "$TOML" \
    && perl -i -pe 's/^#\s*(token = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/$1/' "$TOML" \
    && perl -i -pe 's/^#\s*(pyth = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/pyth-crosschain.git".*\})/$1/' "$TOML" \
    && (sui move test --lint --path packages/deeptrade-core || echo "WARNING: sui move test reported failures")
