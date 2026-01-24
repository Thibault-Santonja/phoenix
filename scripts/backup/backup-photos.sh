#!/usr/bin/env bash
#
# Photos Backup Script
#
# Creates compressed tar archives of uploaded photos with timestamp and retention.
# Designed for production use with Kamal deployment.
#
# Usage:
#   ./backup-photos.sh [environment]
#
# Environment: production (default) | staging
#
# Requirements:
#   - tar and gzip available in PATH
#   - Read permissions for PHOTOS_DIR
#   - Write permissions to BACKUP_DIR
#
# Environment Variables:
#   PHOTOS_DIR           - Photos storage directory (default: ./priv/static/uploads/photos)
#   BACKUP_DIR           - Backup storage directory (default: ./backups/photos)
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
PHOTOS_DIR="${PHOTOS_DIR:-$PROJECT_ROOT/priv/static/uploads/photos}"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups/photos}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="photos_${ENVIRONMENT}_${TIMESTAMP}.tar.gz"
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

    if ! command -v tar &> /dev/null; then
        log_error "tar not found in PATH"
        exit 1
    fi

    if ! command -v gzip &> /dev/null; then
        log_error "gzip not found in PATH"
        exit 1
    fi

    if [ ! -d "$PHOTOS_DIR" ]; then
        log_error "Photos directory not found: $PHOTOS_DIR"
        exit 1
    fi

    log_info "Requirements check passed"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

count_photos() {
    local count=$(find "$PHOTOS_DIR" -type f | wc -l)
    echo "$count"
}

create_backup() {
    log_info "Starting photos backup..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Photos directory: $PHOTOS_DIR"

    local photo_count=$(count_photos)
    log_info "Photos to backup: $photo_count files"

    if [ "$photo_count" -eq 0 ]; then
        log_warn "No photos found in $PHOTOS_DIR"
        log_warn "Creating empty backup marker"
        touch "$BACKUP_PATH"
        return 0
    fi

    log_info "Creating compressed archive: $BACKUP_FILENAME"

    # Create tar.gz archive
    # -c: create archive
    # -z: compress with gzip
    # -f: output file
    # -C: change to directory before archiving
    if tar -czf "$BACKUP_PATH" -C "$(dirname "$PHOTOS_DIR")" "$(basename "$PHOTOS_DIR")"; then
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

    # Check if file is empty (no photos case)
    if [ ! -s "$BACKUP_PATH" ]; then
        log_info "Empty backup verified (no photos)"
        return 0
    fi

    # Verify tar.gz integrity
    if tar -tzf "$BACKUP_PATH" > /dev/null 2>&1; then
        local file_count=$(tar -tzf "$BACKUP_PATH" | wc -l)
        log_info "Backup integrity verified: $file_count entries"
        return 0
    else
        log_error "Backup verification failed - archive may be corrupted"
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
    done < <(find "$BACKUP_DIR" -name "photos_${ENVIRONMENT}_*.tar.gz" -type f -mtime +"$BACKUP_RETENTION_DAYS" -print0)

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
            if aws s3 cp "$BACKUP_PATH" "s3://$BACKUP_S3_BUCKET/photos/$BACKUP_FILENAME"; then
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
    log_info "Source: $PHOTOS_DIR"
    log_info "Backup file: $BACKUP_PATH"

    if [ -s "$BACKUP_PATH" ]; then
        log_info "File size: $(du -h "$BACKUP_PATH" | cut -f1)"
        log_info "Files backed up: $(count_photos)"
    else
        log_info "File size: 0 (no photos)"
    fi

    log_info "Retention: $BACKUP_RETENTION_DAYS days"
    log_info "=========================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Starting photos backup for $ENVIRONMENT"

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
