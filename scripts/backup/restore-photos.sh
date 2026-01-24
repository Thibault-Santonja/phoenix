#!/usr/bin/env bash
#
# Photos Restore Script
#
# Restores photos from a backup tar.gz archive.
# DANGEROUS: This will REPLACE existing photos.
#
# Usage:
#   ./restore-photos.sh <backup_file> [--merge]
#
# Options:
#   --merge    Merge with existing photos (don't delete existing files)
#
# Example:
#   ./restore-photos.sh backups/photos/photos_production_20250113_143022.tar.gz
#   ./restore-photos.sh backups/photos/photos_production_20250113_143022.tar.gz --merge
#
# Requirements:
#   - tar and gunzip available in PATH
#   - Write permissions to PHOTOS_DIR
#
# Environment Variables:
#   PHOTOS_DIR - Photos storage directory (default: ./priv/static/uploads/photos)
#
# Exit codes:
#   0 - Success
#   1 - Configuration/validation error
#   2 - Restore failed

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

BACKUP_FILE="${1:-}"
MERGE_MODE=false

# Check for --merge flag
if [ "${2:-}" = "--merge" ]; then
    MERGE_MODE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PHOTOS_DIR="${PHOTOS_DIR:-$PROJECT_ROOT/priv/static/uploads/photos}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_danger() {
    echo -e "${RED}[DANGER]${NC} $1"
}

usage() {
    echo "Usage: $0 <backup_file> [--merge]"
    echo ""
    echo "Restore photos from a backup archive."
    echo ""
    echo "Options:"
    echo "  --merge    Merge with existing photos (don't delete existing)"
    echo ""
    echo "Example:"
    echo "  $0 backups/photos/photos_production_20250113_143022.tar.gz"
    echo "  $0 backups/photos/photos_production_20250113_143022.tar.gz --merge"
    echo ""
    exit 1
}

check_requirements() {
    log_info "Checking requirements..."

    if ! command -v tar &> /dev/null; then
        log_error "tar not found in PATH"
        exit 1
    fi

    if [ -z "$BACKUP_FILE" ]; then
        log_error "Backup file not specified"
        usage
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    log_info "Requirements check passed"
}

confirm_restore() {
    if [ "$MERGE_MODE" = true ]; then
        log_info "========================================="
        log_info "MERGE MODE: Photos Restore"
        log_info "========================================="
        log_info "This will:"
        log_info "  - Extract photos from: $BACKUP_FILE"
        log_info "  - Merge with existing photos"
        log_info "  - Existing photos will NOT be deleted"
        log_info "========================================="
    else
        log_danger "========================================="
        log_danger "WARNING: PHOTOS RESTORE"
        log_danger "========================================="
        log_danger "This will:"
        log_danger "  1. DELETE all existing photos"
        log_danger "  2. Restore from: $BACKUP_FILE"
        log_danger ""
        log_danger "ALL CURRENT PHOTOS WILL BE LOST!"
        log_danger "========================================="
    fi

    echo ""
    read -p "Type 'yes' to continue: " confirmation

    if [ "$confirmation" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi

    log_warn "Proceeding with restore..."
}

verify_backup() {
    log_info "Verifying backup file integrity..."

    # Check if file is empty (no photos backup case)
    if [ ! -s "$BACKUP_FILE" ]; then
        log_warn "Empty backup file (no photos to restore)"
        return 0
    fi

    if tar -tzf "$BACKUP_FILE" > /dev/null 2>&1; then
        local file_count=$(tar -tzf "$BACKUP_FILE" | wc -l)
        log_info "Backup file verified: $file_count entries"
    else
        log_error "Backup file is corrupted or not a valid tar.gz archive"
        exit 1
    fi
}

backup_existing_photos() {
    if [ -d "$PHOTOS_DIR" ] && [ "$(ls -A "$PHOTOS_DIR")" ]; then
        local backup_name="photos_pre_restore_$(date +%Y%m%d_%H%M%S)"
        local backup_path="$PROJECT_ROOT/backups/photos/$backup_name.tar.gz"

        log_info "Creating safety backup of existing photos..."
        log_info "Safety backup: $backup_path"

        mkdir -p "$(dirname "$backup_path")"
        tar -czf "$backup_path" -C "$(dirname "$PHOTOS_DIR")" "$(basename "$PHOTOS_DIR")"

        log_info "Safety backup created"
    fi
}

clear_existing_photos() {
    if [ "$MERGE_MODE" = true ]; then
        log_info "Merge mode: keeping existing photos"
        return 0
    fi

    if [ -d "$PHOTOS_DIR" ]; then
        log_info "Removing existing photos..."
        rm -rf "$PHOTOS_DIR"
        log_info "Existing photos removed"
    fi
}

restore_photos() {
    log_info "Starting photos restore..."
    log_info "Target directory: $PHOTOS_DIR"

    # Check if backup is empty
    if [ ! -s "$BACKUP_FILE" ]; then
        log_info "Empty backup - no photos to restore"
        return 0
    fi

    # Create parent directory
    mkdir -p "$(dirname "$PHOTOS_DIR")"

    # Extract tar.gz archive
    if tar -xzf "$BACKUP_FILE" -C "$(dirname "$PHOTOS_DIR")"; then
        local restored_count=$(find "$PHOTOS_DIR" -type f | wc -l)
        log_info "Photos restored successfully: $restored_count files"
        return 0
    else
        log_error "Photos restore failed"
        return 2
    fi
}

print_summary() {
    log_info "===== Restore Summary ====="
    log_info "Backup file: $BACKUP_FILE"
    log_info "Target directory: $PHOTOS_DIR"
    log_info "Mode: $([ "$MERGE_MODE" = true ] && echo "MERGE" || echo "REPLACE")"

    if [ -d "$PHOTOS_DIR" ]; then
        local file_count=$(find "$PHOTOS_DIR" -type f | wc -l)
        log_info "Photos in directory: $file_count files"
    fi

    log_info "==========================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Photos Restore"

    check_requirements
    verify_backup
    confirm_restore
    backup_existing_photos
    clear_existing_photos
    restore_photos || exit 2
    print_summary

    log_info "Restore completed successfully"
}

main "$@"
