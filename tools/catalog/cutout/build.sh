#!/bin/sh
# Compila il CLI di scontorno in tools/catalog/out/bin/cutout.
set -e
cd "$(dirname "$0")/.."
mkdir -p out/bin
swiftc -O cutout/main.swift -o out/bin/cutout
echo "out/bin/cutout pronto"
