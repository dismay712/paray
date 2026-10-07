#!/bin/sh

set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
name=${1:?asset name}
arch=${2:?architecture}
out=${3:?destination}
record=$(jq -ce --arg name "$name" --arg arch "$arch" '.assets[$name] | .[$arch] // .any' "$root/versions.lock.json")
url=$(printf '%s' "$record" | jq -er '.url')
hash=$(printf '%s' "$record" | jq -er '.sha256 | select(test("^[0-9a-f]{64}$"))')
mkdir -p "$(dirname "$out")"
trap 'rm -f "$out.part"' EXIT HUP INT TERM
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 300 \
    --proto '=https' --proto-redir '=https' "$url" -o "$out.part"
printf '%s  %s\n' "$hash" "$out.part" | sha256sum -c -
mv "$out.part" "$out"
