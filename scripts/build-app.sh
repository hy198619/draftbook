#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
scratch_dir="$project_dir/.build"
bundle_dir="$project_dir/dist/草稿本.app"
contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
asset_catalog="$project_dir/Resources/Assets.xcassets"
asset_info_plist="$scratch_dir/asset-info.plist"
signing_identity="${CODESIGN_IDENTITY:--}"

export CLANG_MODULE_CACHE_PATH="$scratch_dir/ModuleCache"
export SWIFT_MODULECACHE_PATH="$scratch_dir/ModuleCache"

build_args=(
  --package-path "$project_dir"
  --scratch-path "$scratch_dir"
  --disable-sandbox
  -c release
)

if [[ "${UNIVERSAL_BUILD:-1}" == "1" ]]; then
  build_args+=(--arch arm64 --arch x86_64)
fi

swift build "${build_args[@]}"

bin_dir=$(swift build "${build_args[@]}" --show-bin-path)

rm -rf "$bundle_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$bin_dir/DraftBook" "$macos_dir/DraftBook"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp -R "$project_dir/Resources/ThirdParty" "$resources_dir/ThirdParty"
chmod +x "$macos_dir/DraftBook"

xcrun actool "$asset_catalog" \
  --compile "$resources_dir" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$asset_info_plist"

codesign_args=(--force --sign "$signing_identity" --options runtime)
if [[ "$signing_identity" != "-" ]]; then
  codesign_args+=(--timestamp)
fi

codesign "${codesign_args[@]}" "$bundle_dir"
codesign --verify --deep --strict --verbose=2 "$bundle_dir"
lipo -info "$macos_dir/DraftBook"

echo "$bundle_dir"
