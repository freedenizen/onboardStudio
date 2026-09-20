#!/bin/bash
# Rasterises the vector sources in Design/ into the app and document icons.
# See docs/architecture.md → Icons.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift Scripts/make-icons.swift
