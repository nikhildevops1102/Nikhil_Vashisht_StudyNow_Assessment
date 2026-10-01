#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="/opt/study-now/mern-stack-example"
BACKUP_DIR="/var/backups/study-now/mongodb"

ENV_FILE="$PROJECT_DIR/.env"
PASSPHRASE_FILE="/etc/study-now/backup-passphrase"

R2_PROFILE="study-now-r2"
R2_BUCKET="study-now-mongodb-backups"
R2_ENDPOINT="https://27acea171c3c36c12cc0ea920e598000.r2.cloudflarestorage.com"

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
ARCHIVE="${BACKUP_DIR}/mongodb-${TIMESTAMP}.archive.gz"
ENCRYPTED="${ARCHIVE}.gpg"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

cleanup() {
    rm -f "$ARCHIVE"
}

trap cleanup EXIT

[[ -f "$ENV_FILE" ]] || fail "Environment file not found."
[[ -f "$PASSPHRASE_FILE" ]] || fail "GPG passphrase file not found."

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

MONGO_ROOT_PASSWORD="$(
    awk -F= '$1=="MONGO_ROOT_PASSWORD"{print substr($0,index($0,"=")+1)}' "$ENV_FILE"
)"

[[ -n "$MONGO_ROOT_PASSWORD" ]] || fail "MongoDB root password not found."

log "Creating MongoDB backup..."

docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T mongodb \
    mongodump \
    --username admin \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db employees \
    --archive \
    --gzip \
    > "$ARCHIVE"

[[ -s "$ARCHIVE" ]] || fail "MongoDB backup archive is empty."

log "Encrypting backup..."

gpg \
    --batch \
    --yes \
    --pinentry-mode loopback \
    --passphrase-file "$PASSPHRASE_FILE" \
    --symmetric \
    --cipher-algo AES256 \
    --output "$ENCRYPTED" \
    "$ARCHIVE"

[[ -s "$ENCRYPTED" ]] || fail "Encrypted backup was not created."

rm -f "$ARCHIVE"

log "Uploading encrypted backup to Cloudflare R2..."

aws s3 cp \
    "$ENCRYPTED" \
    "s3://${R2_BUCKET}/mongodb/${TIMESTAMP}.archive.gz.gpg" \
    --profile "$R2_PROFILE" \
    --endpoint-url "$R2_ENDPOINT"

log "Verifying R2 object..."

aws s3api head-object \
    --bucket "$R2_BUCKET" \
    --key "mongodb/${TIMESTAMP}.archive.gz.gpg" \
    --profile "$R2_PROFILE" \
    --endpoint-url "$R2_ENDPOINT" \
    >/dev/null

log "Cleaning up encrypted local backups older than 7 days..."

find "$BACKUP_DIR" \
    -type f \
    -name 'mongodb-*.archive.gz.gpg' \
    -mtime +7 \
    -delete
log "Backup completed successfully."
log "Encrypted backup: $ENCRYPTED"
