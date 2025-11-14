#!/usr/bin/env bash
#
# PostgreSQL Backup Script
#
# Creates compressed PostgreSQL backups with timestamp and retention management.
# Designed for production use with Kamal deployment.
#
# Usage:
#   ./backup-postgres.sh [environment]
#
# Environment: production (default) | staging
#
# Requirements:
#   - pg_dump available in PATH
#   - Database credentials configured via ENV vars or .env file
#   - Write permissions to BACKUP_DIR
#
# Environment Variables:
#   DATABASE_URL          - PostgreSQL connection string
#   BACKUP_DIR           - Backup storage directory (default: ./backups/postgres)
#   BACKUP_RETENTION_DAYS - Number of days to keep backups (default: 30)
#   BACKUP_S3_BUCKET     - Optional: S3 bucket for remote backup
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
#   2 - Backup creation failed
#   3 - Cleanup failed (backup still created)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

ENVIRONMENT="${1:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups/postgres}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="postgres_${ENVIRONMENT}_${TIMESTAMP}.sql.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILENAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_requirements() {
    log_info "Checking requirements..."

    if ! command -v pg_dump &> /dev/null; then
        log_error "pg_dump not found in PATH"
        exit 1
    fi

    if [ -z "${DATABASE_URL:-}" ]; then
        log_error "DATABASE_URL environment variable not set"
        exit 1
    fi

    log_info "Requirements check passed"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

create_backup() {
    log_info "Starting PostgreSQL backup..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Backup file: $BACKUP_FILENAME"

    # Create backup with pg_dump
    # --no-owner: don't output commands to set ownership
    # --no-acl: don't output commands to set access privileges
    # --clean: include commands to clean (drop) database objects
    # --if-exists: use IF EXISTS when dropping objects
    # --format=plain: output as plain SQL
    if pg_dump "$DATABASE_URL" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --format=plain \
        | gzip > "$BACKUP_PATH"; then

        local size=$(du -h "$BACKUP_PATH" | cut -f1)
        log_info "Backup created successfully: $size"
        return 0
    else
        log_error "Backup creation failed"
        return 2
    fi
}

verify_backup() {
    log_info "Verifying backup integrity..."

    if gzip -t "$BACKUP_PATH" 2>/dev/null; then
        log_info "Backup integrity verified"
        return 0
    else
        log_error "Backup verification failed - file may be corrupted"
        return 2
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."

    local deleted_count=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted_count++))
        log_info "Deleted old backup: $(basename "$file")"
    done < <(find "$BACKUP_DIR" -name "postgres_${ENVIRONMENT}_*.sql.gz" -type f -mtime +"$BACKUP_RETENTION_DAYS" -print0)

    if [ $deleted_count -eq 0 ]; then
        log_info "No old backups to clean up"
    else
        log_info "Cleaned up $deleted_count old backup(s)"
    fi
}

upload_to_s3() {
    if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
        log_info "Uploading backup to S3: $BACKUP_S3_BUCKET"

        if command -v aws &> /dev/null; then
            if aws s3 cp "$BACKUP_PATH" "s3://$BACKUP_S3_BUCKET/postgres/$BACKUP_FILENAME"; then
                log_info "Backup uploaded to S3 successfully"
            else
                log_warn "Failed to upload backup to S3 (backup still saved locally)"
            fi
        else
            log_warn "AWS CLI not found, skipping S3 upload"
        fi
    fi
}

print_summary() {
    log_info "===== Backup Summary ====="
    log_info "Environment: $ENVIRONMENT"
    log_info "Backup file: $BACKUP_PATH"
    log_info "File size: $(du -h "$BACKUP_PATH" | cut -f1)"
    log_info "Retention: $BACKUP_RETENTION_DAYS days"
    log_info "=========================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Starting PostgreSQL backup for $ENVIRONMENT"

    check_requirements
    create_backup_directory
    create_backup || exit 2
    verify_backup || exit 2
    cleanup_old_backups || log_warn "Cleanup failed but backup was created"
    upload_to_s3 || true  # Non-critical, don't fail
    print_summary

    log_info "Backup completed successfully"
}

main "$@"
