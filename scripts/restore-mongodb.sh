#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="/opt/study-now/mern-stack-example"
RESTORE_DIR="/var/backups/study-now/restore"

ENV_FILE="$PROJECT_DIR/.env"
PASSPHRASE_FILE="/etc/study-now/backup-passphrase"

R2_PROFILE="study-now-r2"
R2_BUCKET="study-now-mongodb-backups"
R2_ENDPOINT="https://27acea171c3c36c12cc0ea920e598000.r2.cloudflarestorage.com"

MONGO_CONTAINER="study-now-mongodb"

usage() {
    echo "Usage:"
    echo "  $0 <R2_OBJECT_KEY> --drop"
    echo
    echo "Example:"
    echo "  $0 mongodb/20261001T231321Z.archive.gz.gpg --drop"
    exit 1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || usage

R2_KEY="$1"
DROP_FLAG="$2"

[[ "$DROP_FLAG" == "--drop" ]] || usage

[[ -f "$ENV_FILE" ]] || fail "Environment file not found."
[[ -f "$PASSPHRASE_FILE" ]] || fail "GPG passphrase file not found."

MONGO_ROOT_PASSWORD="$(
    awk -F= '$1=="MONGO_ROOT_PASSWORD"{print substr($0,index($0,"=")+1)}' "$ENV_FILE"
)"

[[ -n "$MONGO_ROOT_PASSWORD" ]] || fail "MongoDB root password not found."

docker inspect "$MONGO_CONTAINER" >/dev/null 2>&1 \
    || fail "MongoDB container is not running."

mkdir -p "$RESTORE_DIR"
chmod 700 "$RESTORE_DIR"

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"

ENCRYPTED_FILE="$RESTORE_DIR/restore-${TIMESTAMP}.archive.gz.gpg"
ARCHIVE_FILE="$RESTORE_DIR/restore-${TIMESTAMP}.archive.gz"
CONTAINER_ARCHIVE="/tmp/study-now-restore-${TIMESTAMP}.archive.gz"

cleanup() {
    rm -f "$ENCRYPTED_FILE" "$ARCHIVE_FILE"
    docker exec "$MONGO_CONTAINER" rm -f "$CONTAINER_ARCHIVE" >/dev/null 2>&1 || true
}

trap cleanup EXIT

log "Downloading encrypted backup from Cloudflare R2..."

aws s3 cp \
    "s3://${R2_BUCKET}/${R2_KEY}" \
    "$ENCRYPTED_FILE" \
    --profile "$R2_PROFILE" \
    --endpoint-url "$R2_ENDPOINT"

[[ -s "$ENCRYPTED_FILE" ]] || fail "Downloaded backup is empty."

log "Decrypting backup..."

gpg \
    --batch \
    --yes \
    --pinentry-mode loopback \
    --passphrase-file "$PASSPHRASE_FILE" \
    --output "$ARCHIVE_FILE" \
    --decrypt "$ENCRYPTED_FILE"

[[ -s "$ARCHIVE_FILE" ]] || fail "Decrypted archive is empty."

log "Copying restore archive into MongoDB container..."

docker cp \
    "$ARCHIVE_FILE" \
    "${MONGO_CONTAINER}:${CONTAINER_ARCHIVE}"

log "Verifying MongoDB backup archive..."

docker exec "$MONGO_CONTAINER" \
    mongorestore \
    --username admin \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --gzip \
    --archive="$CONTAINER_ARCHIVE" \
    --dryRun \
    >/dev/null

log "Backup archive verification passed."

echo
echo "WARNING: This will DROP the employees database before restoring it."
echo "Backup object: $R2_KEY"
echo
read -r -p "Type RESTORE to continue: " CONFIRM

[[ "$CONFIRM" == "RESTORE" ]] || fail "Restore cancelled."

log "Dropping employees database..."

docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    --username admin \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('employees').dropDatabase()"

log "Restoring MongoDB backup..."

docker exec "$MONGO_CONTAINER" \
    mongorestore \
    --username admin \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --gzip \
    --archive="$CONTAINER_ARCHIVE"

log "Checking application health..."

curl --fail --silent --show-error \
    http://localhost:8080/health

echo
log "Restore completed successfully."
