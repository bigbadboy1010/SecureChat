#!/bin/sh
set -eu
bridge=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$bridge/../.." && pwd)
build_root=$(CDPATH= cd -- "$repo/.." && pwd)
export RUSTFLAGS="--remap-path-prefix=$build_root=PrivateRoomBuild"
cd "$bridge"
# Use the exact Rust release from rust-toolchain.toml and verified Cargo.lock.
# Set CARGO_HOME / RUSTUP_HOME to workspace-owned directories when appropriate.
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo +1.90.0 build --release --locked --target "$target"
done
mkdir -p target/universal-sim
lipo -create target/aarch64-apple-ios-sim/release/libprivateroom_olm.a target/x86_64-apple-ios/release/libprivateroom_olm.a -output target/universal-sim/libprivateroom_olm.a
# Do not silently replace an existing review artifact. Move it aside first.
output=${1:-"$repo/Vendor/PrivateRoomOlm.xcframework"}
xcodebuild -create-xcframework \
    -library "$bridge/target/aarch64-apple-ios/release/libprivateroom_olm.a" -headers "$bridge/include" \
    -library "$bridge/target/universal-sim/libprivateroom_olm.a" -headers "$bridge/include" \
    -output "$output"
find "$output" -type f -exec shasum -a 256 {} \;
