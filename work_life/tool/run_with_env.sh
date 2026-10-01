#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$project_root/config/.env"

if [ ! -f "$env_file" ]; then
  echo "Missing config/.env. Copy config/.env.example and add your local keys." >&2
  exit 1
fi

set -a
. "$env_file"
set +a

: "${SUPABASE_URL:?Add SUPABASE_URL to config/.env}"
: "${SUPABASE_PUBLISHABLE_KEY:?Add SUPABASE_PUBLISHABLE_KEY to config/.env}"
AIMLAPI_MODEL=${AIMLAPI_MODEL:-google/gemini-3-8-flash}
AIMLAPI_BASE_URL=${AIMLAPI_BASE_URL:-https://api.aimlapi.com/v1}
AIMLAPI_KEY=${AIMLAPI_KEY:-}
WORK_LIFE_AI_PROXY_URL=${WORK_LIFE_AI_PROXY_URL:-}
ALLOW_INSECURE_LOCAL_AI=${ALLOW_INSECURE_LOCAL_AI:-false}
if [ -z "$WORK_LIFE_AI_PROXY_URL" ] && [ "$ALLOW_INSECURE_LOCAL_AI" != "true" ]; then
  echo "Set WORK_LIFE_AI_PROXY_URL, or explicitly enable debug-only ALLOW_INSECURE_LOCAL_AI=true." >&2
  exit 1
fi

# Reuse the project-local Android toolchain when it is installed. These values
# are harmless for iOS runs and avoid requiring global Java/Android setup.
if [ -z "${JAVA_HOME:-}" ] && [ -d "$project_root/.tooling/java/jdk-17.0.20.1+1/Contents/Home" ]; then
  export JAVA_HOME="$project_root/.tooling/java/jdk-17.0.20.1+1/Contents/Home"
fi
if [ -z "${ANDROID_HOME:-}" ] && [ -d "$project_root/.tooling/android-sdk" ]; then
  export ANDROID_HOME="$project_root/.tooling/android-sdk"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${ANDROID_HOME:+$ANDROID_HOME/platform-tools:}/Users/rioo/flutter/bin:$PATH"

cd "$project_root"
exec /Users/rioo/flutter/bin/flutter run \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define="WORK_LIFE_AI_PROXY_URL=$WORK_LIFE_AI_PROXY_URL" \
  --dart-define="ALLOW_INSECURE_LOCAL_AI=$ALLOW_INSECURE_LOCAL_AI" \
  --dart-define="AIMLAPI_KEY=$AIMLAPI_KEY" \
  --dart-define="AIMLAPI_MODEL=$AIMLAPI_MODEL" \
  --dart-define="AIMLAPI_BASE_URL=$AIMLAPI_BASE_URL" \
  "$@"
