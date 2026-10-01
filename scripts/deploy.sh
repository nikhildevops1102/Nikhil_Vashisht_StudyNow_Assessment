#!/usr/bin/env bash

set -Eeuo pipefail

COMPOSE="docker compose"
BACKEND_FILE="nginx/active-backend.conf"
PUBLIC_HEALTH_URL="http://localhost:8080/health"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ ! -f "$BACKEND_FILE" ]]; then
    fail "Active backend file not found: $BACKEND_FILE"
fi

#CURRENT_BACKEND="$(awk '/server (api-blue|api-green):5050;/{print $2}' "$BACKEND_FILE" | tr -d ';')"
CURRENT_BACKEND="$(awk '/server (api-blue|api-green):5050;/{print $2}' "$BACKEND_FILE" | sed 's/:5050;//')"

case "$CURRENT_BACKEND" in
    api-blue)
        ACTIVE_COLOR="blue"
        INACTIVE_COLOR="green"
        ;;
    api-green)
        ACTIVE_COLOR="green"
        INACTIVE_COLOR="blue"
        ;;
    *)
        fail "Unable to determine active backend from $BACKEND_FILE"
        ;;
esac

log "Active backend: $ACTIVE_COLOR"
log "Deployment target: $INACTIVE_COLOR"

INACTIVE_SERVICE="api-$INACTIVE_COLOR"

log "Building $INACTIVE_SERVICE..."
$COMPOSE build "$INACTIVE_SERVICE"

log "Starting $INACTIVE_SERVICE..."
$COMPOSE up -d "$INACTIVE_SERVICE"

log "Waiting for $INACTIVE_SERVICE to become healthy..."

for i in {1..30}; do
    STATUS="$($COMPOSE ps --format '{{.Service}} {{.Health}}' "$INACTIVE_SERVICE" 2>/dev/null || true)"

    if echo "$STATUS" | grep -q "$INACTIVE_SERVICE healthy"; then
        log "$INACTIVE_SERVICE is healthy."
        break
    fi

    if [[ "$i" -eq 30 ]]; then
        fail "$INACTIVE_SERVICE did not become healthy."
    fi

    sleep 2
done

log "Verifying $INACTIVE_SERVICE health endpoint..."

if ! $COMPOSE exec -T "$INACTIVE_SERVICE" \
    node -e "fetch('http://127.0.0.1:5050/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
then
    fail "$INACTIVE_SERVICE health endpoint failed."
fi

PREVIOUS_BACKEND="$(cat "$BACKEND_FILE")"
NEW_BACKEND="server ${INACTIVE_SERVICE}:5050;"

rollback() {
    log "Deployment verification failed. Rolling back to $ACTIVE_COLOR..."
    printf '%s\n' "$PREVIOUS_BACKEND" > "$BACKEND_FILE"

    if docker exec study-now-nginx nginx -t >/dev/null 2>&1; then
        docker exec study-now-nginx nginx -s reload >/dev/null
        log "Nginx rolled back to $ACTIVE_COLOR."
    else
        log "WARNING: Nginx rollback configuration test failed."
    fi

    exit 1
}

trap rollback ERR

log "Switching Nginx from $ACTIVE_COLOR to $INACTIVE_COLOR..."
printf '%s\n' "$NEW_BACKEND" > "$BACKEND_FILE"

log "Validating Nginx configuration..."
docker exec study-now-nginx nginx -t

#log "Reloading Nginx..."
#docker exec study-now-nginx nginx -s reload

log "Reloading Nginx..."
docker exec study-now-nginx nginx -s reload

#if [[ "${DEPLOYMENT_TEST_FAIL:-0}" == "1" ]]; then
#    echo "Intentional failure for rollback drill."
#    false
#fi

log "Verifying production health endpoint..."

for i in {1..10}; do
    if curl -fsS "$PUBLIC_HEALTH_URL" >/dev/null; then
        log "Production health check passed."
        break
    fi

    if [[ "$i" -eq 10 ]]; then
        fail "Production health check failed after traffic switch."
    fi

    sleep 2
done

trap - ERR

log "Deployment successful."
log "Previous backend: $ACTIVE_COLOR"
log "Active backend: $INACTIVE_COLOR"
log "Rollback target remains available: api-$ACTIVE_COLOR"
