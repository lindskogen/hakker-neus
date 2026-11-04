#!/bin/sh
# Downloads the blocking lists and converts them (see easylist-to-webkit.py and AdBlocking.swift):
# EasyList into the Safari content blocker extension, which the built-in browser also reads,
# the others into the app for the built-in browser only. Run before a release.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
convert() {
    curl -sfL "$2" -o "$work/$1.txt"
    python3 -I "$here/tools/easylist-to-webkit.py" "$work/$1.txt" "$here/$3/$1.json"
}
convert easylist https://easylist.to/easylist/easylist.txt ContentBlocker
convert easyprivacy https://easylist.to/easylist/easyprivacy.txt HakkerNeus/BlockingLists
convert cookies https://secure.fanboy.co.nz/fanboy-cookiemonster.txt HakkerNeus/BlockingLists
convert social https://easylist.to/easylist/fanboy-social.txt HakkerNeus/BlockingLists
