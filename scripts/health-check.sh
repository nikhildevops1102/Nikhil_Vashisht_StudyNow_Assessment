#!/usr/bin/env bash

set -Eeuo pipefail

HEALTH_URL="http://localhost:8080/health"
WEBHOOK_FILE="/etc/study-now/health-webhook"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if curl -fsS --max-time 10 "$HEALTH_URL" >/dev/null; then
    log "Health check passed."
    exit 0
fi

log "Health check FAILED."

if [[ -s "$WEBHOOK_FILE" ]]; then
    WEBHOOK_URL="$(cat "$WEBHOOK_FILE")"

    curl -fsS \
        --max-time 10 \
        -H "Content-Type: application/json" \
        -d '{"text":"Study Now application health check failed on the assessment VM."}' \
        "$WEBHOOK_URL" >/dev/null || true

    log "Alert webhook triggered."
else
    log "Webhook configuration not found."
fi

exit 1
