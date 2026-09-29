#!/bin/bash
# 合成した JSON（rulestool build --compose-out）を、指定した版の iOS シミュレーターの WebKit でコンパイルする。
#
# 使い方：.github/scripts/ios-webkit-check.sh <iOS の版（例 18.6）> <file.json>...
#
# - tools/ios-webkit-check をシミュレーター向けにビルドし、使い捨てのシミュレーターを作って動かし、最後に消す
#   （ほかの作業で使っているシミュレーターには触れない）
# - 指定した版のランタイムがなければ失敗する（ランナーのイメージにある版は actions/runner-images の README）
# - GITHUB_STEP_SUMMARY があれば、結果を書き足す
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ $# -lt 2 ]; then
  echo "使い方：$0 <iOS の版> <file.json>..." >&2
  exit 2
fi
version=$1
shift

work=$(mktemp -d)
device=""
cleanup() {
  if [ -n "$device" ]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

echo "▶ 確かめるツールをビルドします（$(xcodebuild -version | head -1)）" >&2
xcrun --sdk iphonesimulator swiftc -swift-version 5 -O \
  -target "$(uname -m)-apple-ios17.0-simulator" \
  tools/ios-webkit-check/main.swift -o "$work/ios-webkit-check"

# 指定した版の iOS のランタイムと、それで使える iPhone の機種を選ぶ
read -r runtime devicetype < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
version = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("platform") == "iOS" and r.get("isAvailable")
            and (r["version"] == version or r["version"].startswith(version + "."))]
if not runtimes:
    sys.exit(1)
runtime = sorted(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
# productFamily がない古い simctl でも選べるように、名前でも見る
iphones = [d["identifier"] for d in runtime.get("supportedDeviceTypes", [])
           if d.get("productFamily") == "iPhone" or d.get("name", "").startswith("iPhone")]
if not iphones:
    sys.exit(1)
print(runtime["identifier"], iphones[0])
' "$version") || { echo "✘ iOS $version のシミュレーターのランタイムがありません" >&2; xcrun simctl list runtimes >&2; exit 1; }

echo "▶ シミュレーターを作ります（$runtime、$devicetype）" >&2
device=$(xcrun simctl create "ios-webkit-check-$$" "$devicetype" "$runtime")
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b >/dev/null

paths=()
for file in "$@"; do
  paths+=("$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")")
done

status=0
output=$(xcrun simctl spawn "$device" "$work/ios-webkit-check" "${paths[@]}" 2>&1) || status=$?
echo "$output"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### iOS $version の WebKit でのコンパイル"
    echo ""
    echo '```'
    echo "$output" | grep -E '^(iOS|✔|✘)'
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$status" -ne 0 ]; then
  echo "✘ iOS $version の WebKit で、コンパイルできないリストがあります（WKErrorDomain 6 なら、この版で使えない書き方）" >&2
fi
exit "$status"
