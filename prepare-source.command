#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
revision=d1a7e8b0816b29029e2066bf9a974253bb4a07c8
if [[ ! -d source ]]; then
  git init source
  git -C source remote add origin https://github.com/proof-native/parano1d.git
  git -C source fetch --depth=1 origin "$revision"
  git -C source checkout --detach FETCH_HEAD
fi
[[ "$(git -C source rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected upstream revision'; exit 1; }
mkdir -p bin
