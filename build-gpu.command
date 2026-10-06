#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash prepare-source.command
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]
. "$HOME/.cargo/env"
[[ "$(git -C source rev-parse HEAD)" == d1a7e8b0816b29029e2066bf9a974253bb4a07c8 ]]
RUSTFLAGS="--remap-path-prefix=$HOME=/builder --remap-path-prefix=$PWD=/noid-miner" cargo +1.96.0 build --locked --release --manifest-path oracle/Cargo.toml
oracle/target/release/noid-metal-oracle export
xcrun swiftc -O -target arm64-apple-macos13.0 MetalMiner.swift -o bin/noid-metal -framework Metal -framework Foundation
shasum -a 256 bin/noid-metal oracle/target/release/noid-metal-oracle tables.bin rounds.bin rounds-tower.bin tower-small.metal > GPU-SHA256SUMS
