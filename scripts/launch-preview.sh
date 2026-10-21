#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
fixture_file="$project_dir/PreviewFixtures/drafts.json"
source_bundle="$project_dir/dist/草稿本.app"

if [[ ! -f "$fixture_file" ]]; then
  echo "Missing preview fixture: $fixture_file" >&2
  exit 1
fi

"$project_dir/scripts/build-app.sh"

preview_root=$(mktemp -d /private/tmp/draftbook-preview.XXXXXX)
preview_data=$(mktemp -d /private/tmp/draftbook-preview-data.XXXXXX)
preview_bundle="$preview_root/草稿本预览.app"

ditto "$source_bundle" "$preview_bundle"
cp "$fixture_file" "$preview_data/drafts.json"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.yangyuxuan.DraftBook.Preview" "$preview_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 草稿本预览" "$preview_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 草稿本预览" "$preview_bundle/Contents/Info.plist"

codesign --force --deep --sign - "$preview_bundle"
DRAFTBOOK_DATA_DIR="$preview_data" open -na "$preview_bundle"

echo "Preview app:  $preview_bundle"
echo "Preview data: $preview_data"
