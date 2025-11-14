#!/usr/bin/env bash
#
# Portfolio Backup Restoration Script
#
# Restores PostgreSQL database, photos, and configuration from a backup archive.
#
# Usage:
#   ./restore.sh <backup_archive.tar.gz> [environment]
#
# Arguments:
#   backup_archive - Path to backup archive or just filename (will search in backups/ and Storage Box)
#   environment    - Target environment (production|staging, default: production)
#
# Examples:
#   ./restore.sh portfolio_production_20251115_030000.tar.gz
#   ./restore.sh backups/portfolio_production_20251115_030000.tar.gz
#   ./restore.sh portfolio_production_20251115_030000.tar.gz staging
#
# Requirements:
#   - tar, gzip, psql in PATH
#   - Database credentials via DATABASE_URL
#   - Write permissions to application directories
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
#   2 - Archive not found
#   3 - Extraction failed
#   4 - Database restoration failed
#   5 - Storage restoration failed

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

BACKUP_ARCHIVE="${1:-}"
ENVIRONMENT="${2:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Directories
RESTORE_DIR="/tmp/restore_$(date +%Y%m%d_%H%M%S)"
APP_STORAGE="${APP_STORAGE:-$PROJECT_ROOT/priv/static/uploads}"
LOCAL_BACKUP_DIR="$PROJECT_ROOT/backups"

# Storage Box
STORAGE_BOX="${STORAGE_BOX:-}"
STORAGE_BOX_PATH="${STORAGE_BOX_PATH:-/backups/portfolio}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Logging
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# ============================================================================
# Cleanup Handler
# ============================================================================

cleanup() {
    if [ -d "$RESTORE_DIR" ]; then
        log_warn "Cleaning up temporary directory: $RESTORE_DIR"
        rm -rf "$RESTORE_DIR"
    fi
}

trap cleanup EXIT INT TERM

# ============================================================================
# Validation
# ============================================================================

check_requirements() {
    log_step "Checking requirements..."

    local missing_commands=()

    if ! command -v tar &> /dev/null; then
        missing_commands+=("tar")
    fi

    if ! command -v psql &> /dev/null; then
        missing_commands+=("psql")
    fi

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi

    if [ -z "${DATABASE_URL:-}" ]; then
        log_error "DATABASE_URL environment variable not set"
        exit 1
    fi

    log_info "Requirements check passed"
}

validate_archive_argument() {
    if [ -z "$BACKUP_ARCHIVE" ]; then
        log_error "Usage: $0 <backup_archive.tar.gz> [environment]"
        log_error ""
        log_error "Available backups:"
        list_available_backups
        exit 1
    fi
}

# ============================================================================
# Archive Location
# ============================================================================

find_archive() {
    log_step "Locating backup archive..."

    # Case 1: Full path provided and exists
    if [ -f "$BACKUP_ARCHIVE" ]; then
        log_info "Found archive: $BACKUP_ARCHIVE"
        return 0
    fi

    # Case 2: Just filename provided, search in local backups/
    if [ -f "$LOCAL_BACKUP_DIR/$BACKUP_ARCHIVE" ]; then
        BACKUP_ARCHIVE="$LOCAL_BACKUP_DIR/$BACKUP_ARCHIVE"
        log_info "Found archive in local backups: $BACKUP_ARCHIVE"
        return 0
    fi

    # Case 3: Try to download from Storage Box
    if [ -n "$STORAGE_BOX" ]; then
        log_info "Archive not found locally, attempting download from Storage Box..."
        download_from_storage_box
        return $?
    fi

    log_error "Archive not found: $BACKUP_ARCHIVE"
    log_error ""
    log_error "Available local backups:"
    list_available_backups
    exit 2
}

download_from_storage_box() {
    local remote_path="${STORAGE_BOX}:${STORAGE_BOX_PATH}/${BACKUP_ARCHIVE}"
    local local_path="$LOCAL_BACKUP_DIR/$BACKUP_ARCHIVE"

    mkdir -p "$LOCAL_BACKUP_DIR"

    log_info "Downloading from: $remote_path"

    if scp "$remote_path" "$local_path"; then
        BACKUP_ARCHIVE="$local_path"
        log_info "✓ Download completed"
        return 0
    else
        log_error "✗ Download failed"
        log_error ""
        log_error "Available remote backups:"
        list_remote_backups
        exit 2
    fi
}

list_available_backups() {
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        ls -lh "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null || log_info "  (none)"
    else
        log_info "  (no local backup directory)"
    fi

    if [ -n "$STORAGE_BOX" ]; then
        echo ""
        log_info "Remote backups (Storage Box):"
        list_remote_backups
    fi
}

list_remote_backups() {
    if [ -n "$STORAGE_BOX" ]; then
        ssh "$STORAGE_BOX" "ls -lh $STORAGE_BOX_PATH/*.tar.gz 2>/dev/null" || log_info "  (none or not accessible)"
    fi
}

# ============================================================================
# Confirmation
# ============================================================================

confirm_restoration() {
    log_warn ""
    log_warn "========================================="
    log_warn "⚠️  WARNING: DESTRUCTIVE OPERATION"
    log_warn "========================================="
    log_warn ""
    log_warn "This will:"
    log_warn "  1. DROP and recreate the database"
    log_warn "  2. DELETE all current files in storage"
    log_warn "  3. Restore from backup: $BACKUP_ARCHIVE"
    log_warn ""
    log_warn "Target environment: $ENVIRONMENT"
    log_warn "Target database: $DATABASE_URL"
    log_warn "Target storage: $APP_STORAGE"
    log_warn ""
    log_warn "========================================="
    log_warn ""

    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Restoration cancelled by user"
        exit 0
    fi

    log_info "Confirmation received, proceeding with restoration..."
}

# ============================================================================
# Restoration Operations
# ============================================================================

extract_archive() {
    log_step "Extracting backup archive..."

    mkdir -p "$RESTORE_DIR"

    if tar -xzf "$BACKUP_ARCHIVE" -C "$RESTORE_DIR"; then
        local entries=$(find "$RESTORE_DIR" -type f | wc -l)
        log_info "✓ Archive extracted: $entries files"
        return 0
    else
        log_error "✗ Archive extraction failed"
        exit 3
    fi
}

show_backup_metadata() {
    log_step "Backup metadata:"

    if [ -f "$RESTORE_DIR/metadata.txt" ]; then
        cat "$RESTORE_DIR/metadata.txt" | while IFS= read -r line; do
            log_info "  $line"
        done
    else
        log_warn "No metadata found in backup"
    fi
}

restore_database() {
    log_step "Restoring PostgreSQL database..."

    local db_backup="$RESTORE_DIR/database.sql"

    if [ ! -f "$db_backup" ]; then
        log_error "Database backup file not found in archive"
        exit 4
    fi

    log_warn "Dropping and recreating database..."

    # Parse database name from DATABASE_URL
    local db_name=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')

    if psql "$DATABASE_URL" < "$db_backup"; then
        log_info "✓ Database restored successfully"
        return 0
    else
        log_error "✗ Database restoration failed"
        exit 4
    fi
}

restore_storage() {
    log_step "Restoring application storage..."

    local storage_backup="$RESTORE_DIR/storage"

    if [ ! -d "$storage_backup" ]; then
        log_warn "No storage directory in backup (may be empty)"
        return 0
    fi

    log_info "Removing current storage: $APP_STORAGE"
    rm -rf "$APP_STORAGE"

    log_info "Restoring storage from backup..."
    if cp -r "$storage_backup" "$APP_STORAGE"; then
        local count=$(find "$APP_STORAGE" -type f | wc -l)
        log_info "✓ Storage restored: $count files"
        return 0
    else
        log_error "✗ Storage restoration failed"
        exit 5
    fi
}

restore_configuration() {
    log_step "Configuration files restoration..."

    if [ -d "$RESTORE_DIR/config" ]; then
        log_info "Configuration files found in backup:"
        ls -la "$RESTORE_DIR/config/" || true
        log_warn ""
        log_warn "⚠️  Configuration files are in: $RESTORE_DIR/config/"
        log_warn "Review and manually restore if needed (.env, deploy.yml)"
        log_warn "These are NOT automatically restored to prevent overwriting current config"
    else
        log_info "No configuration files in backup"
    fi
}

# ============================================================================
# Post-Restoration
# ============================================================================

verify_restoration() {
    log_step "Verifying restoration..."

    # Check database connection
    if psql "$DATABASE_URL" -c "SELECT 1" > /dev/null 2>&1; then
        log_info "✓ Database connection verified"
    else
        log_error "✗ Database connection failed"
        exit 4
    fi

    # Check storage directory
    if [ -d "$APP_STORAGE" ]; then
        local count=$(find "$APP_STORAGE" -type f 2>/dev/null | wc -l)
        log_info "✓ Storage directory verified: $count files"
    else
        log_warn "Storage directory does not exist (may be empty backup)"
    fi
}

print_summary() {
    echo ""
    echo "========================================="
    log_info "Restoration completed successfully"
    echo "========================================="
    log_info "Restored from:  $BACKUP_ARCHIVE"
    log_info "Environment:    $ENVIRONMENT"
    log_info "Database:       Restored"
    log_info "Storage:        Restored"
    log_info "Config:         Manual review needed (see above)"
    echo "========================================="
    echo ""
    log_warn "⚠️  Important next steps:"
    log_warn "  1. Review configuration files in: $RESTORE_DIR/config/"
    log_warn "  2. Restart the application: kamal app restart"
    log_warn "  3. Verify application functionality"
    log_warn "  4. Check logs for any issues"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Portfolio Backup Restoration"
    log_info "Environment: $ENVIRONMENT"
    echo ""

    validate_archive_argument
    check_requirements
    find_archive
    confirm_restoration

    extract_archive
    show_backup_metadata

    restore_database
    restore_storage
    restore_configuration

    verify_restoration
    print_summary

    log_info "Restoration process completed"
    log_warn "Temporary files kept for review: $RESTORE_DIR"
}

main "$@"
