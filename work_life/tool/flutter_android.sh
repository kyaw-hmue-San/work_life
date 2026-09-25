#!/bin/sh
# Project-local Android toolchain; no global shell configuration is changed.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export JAVA_HOME="${JAVA_HOME:-$project_root/.tooling/java/jdk-17.0.20.1+1/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$project_root/.tooling/android-sdk}"
export PATH="/Users/rioo/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
exec /Users/rioo/flutter/bin/flutter "$@"
