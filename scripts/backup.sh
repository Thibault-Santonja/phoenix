#!/usr/bin/env bash
#
# Portfolio Unified Backup Script
#
# Creates comprehensive backups of PostgreSQL database, photos, and configuration.
# Uploads to Hetzner Storage Box with automatic retention management.
#
# This script consolidates database and photo backups into a single archive
# for simplified backup management and restoration.
#
# Usage:
#   ./backup.sh [environment]
#
# Environment: production (default) | staging
#
# Requirements:
#   - pg_dump, tar, gzip in PATH
#   - SSH access to Hetzner Storage Box configured
#   - Database credentials via DATABASE_URL
#   - Write permissions to local directories
#
# Environment Variables:
#   DATABASE_URL              - PostgreSQL connection string
#   APP_STORAGE               - Application storage directory (default: ./priv/static/uploads)
#   BACKUP_DIR                - Local backup directory (default: ./backups)
#   STORAGE_BOX               - Storage Box SSH target (e.g., u123456@u123456.your-storagebox.de)
#   STORAGE_BOX_PATH          - Remote backup path (default: /backups/portfolio)
#   BACKUP_RETENTION_DAYS     - Days to keep backups (default: 7)
#   NOTIFICATION_WEBHOOK      - Optional webhook URL for notifications
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
#   2 - Database backup failed
#   3 - Photos backup failed
#   4 - Archive creation failed
#   5 - Upload failed
#   6 - Verification failed

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

ENVIRONMENT="${1:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Timestamps
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATE_LABEL=$(date +"%Y-%m-%d %H:%M:%S")

# Directories
APP_STORAGE="${APP_STORAGE:-$PROJECT_ROOT/priv/static/uploads}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/backup_${TIMESTAMP}}"
LOCAL_ARCHIVE_DIR="${LOCAL_ARCHIVE_DIR:-$PROJECT_ROOT/backups}"

# Storage Box configuration
STORAGE_BOX="${STORAGE_BOX:-}"
STORAGE_BOX_PATH="${STORAGE_BOX_PATH:-/backups/portfolio}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Archive naming
ARCHIVE_NAME="portfolio_${ENVIRONMENT}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$LOCAL_ARCHIVE_DIR/$ARCHIVE_NAME"

# Notification
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Logging and Notifications
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $DATE_LABEL - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $DATE_LABEL - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $DATE_LABEL - $1" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

send_notification() {
    local status=$1
    local message=$2

    if [ -n "$NOTIFICATION_WEBHOOK" ]; then
        local payload="{\"status\":\"$status\",\"message\":\"$message\",\"timestamp\":\"$DATE_LABEL\"}"
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --silent --show-error || log_warn "Failed to send notification"
    fi

    log_info "Notification: Backup $status - $message"
}

# ============================================================================
# Cleanup Handler
# ============================================================================

cleanup() {
    local exit_code=$?

    if [ -d "$BACKUP_DIR" ]; then
        log_warn "Cleaning up temporary directory: $BACKUP_DIR"
        rm -rf "$BACKUP_DIR"
    fi

    if [ $exit_code -ne 0 ]; then
        log_error "Backup failed with exit code $exit_code"
        send_notification "FAILED" "Backup failed at $(date)"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

# ============================================================================
# Validation
# ============================================================================

check_requirements() {
    log_step "Checking requirements..."

    local missing_commands=()

    if ! command -v pg_dump &> /dev/null; then
        missing_commands+=("pg_dump")
    fi

    if ! command -v tar &> /dev/null; then
        missing_commands+=("tar")
    fi

    if ! command -v gzip &> /dev/null; then
        missing_commands+=("gzip")
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

check_storage_box_config() {
    if [ -n "$STORAGE_BOX" ]; then
        log_info "Storage Box configured: $STORAGE_BOX"

        # Test SSH connection
        if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$STORAGE_BOX" exit 2>/dev/null; then
            log_error "Cannot connect to Storage Box via SSH"
            log_error "Please configure SSH key authentication"
            exit 1
        fi

        log_info "Storage Box connection verified"
    else
        log_warn "STORAGE_BOX not configured - backups will only be stored locally"
    fi
}

# ============================================================================
# Backup Operations
# ============================================================================

create_backup_structure() {
    log_step "Creating backup directory structure..."

    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/config"
    mkdir -p "$LOCAL_ARCHIVE_DIR"

    log_info "Backup directory: $BACKUP_DIR"
}

backup_database() {
    log_step "Backing up PostgreSQL database..."

    local db_backup="$BACKUP_DIR/database.sql"

    if pg_dump "$DATABASE_URL" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --format=plain > "$db_backup"; then

        local size=$(du -h "$db_backup" | cut -f1)
        log_info "✓ Database backup completed: $size"
        return 0
    else
        log_error "✗ Database backup failed"
        return 2
    fi
}

backup_storage() {
    log_step "Backing up application storage..."

    if [ ! -d "$APP_STORAGE" ]; then
        log_warn "Storage directory not found: $APP_STORAGE"
        log_warn "Creating empty marker"
        mkdir -p "$BACKUP_DIR/storage"
        return 0
    fi

    if cp -r "$APP_STORAGE" "$BACKUP_DIR/storage"; then
        local size=$(du -sh "$BACKUP_DIR/storage" | cut -f1)
        local count=$(find "$BACKUP_DIR/storage" -type f | wc -l)
        log_info "✓ Storage backup completed: $size ($count files)"
        return 0
    else
        log_error "✗ Storage backup failed"
        return 3
    fi
}

backup_configuration() {
    log_step "Backing up configuration files..."

    # Backup .env if exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        cp "$PROJECT_ROOT/.env" "$BACKUP_DIR/config/" 2>/dev/null || log_warn "Could not copy .env"
    fi

    # Backup deploy.yml if exists
    if [ -f "$PROJECT_ROOT/config/deploy.yml" ]; then
        cp "$PROJECT_ROOT/config/deploy.yml" "$BACKUP_DIR/config/" 2>/dev/null || log_warn "Could not copy deploy.yml"
    fi

    # Create backup metadata
    cat > "$BACKUP_DIR/metadata.txt" <<EOF
Backup Information
==================
Environment: $ENVIRONMENT
Timestamp: $DATE_LABEL
Hostname: $(hostname)
User: $(whoami)
Elixir Version: $(elixir --version 2>/dev/null | head -1 || echo "N/A")
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
EOF

    log_info "✓ Configuration backed up"
}

create_archive() {
    log_step "Creating compressed archive..."

    if tar -czf "$ARCHIVE_PATH" -C "$BACKUP_DIR" .; then
        local size=$(du -h "$ARCHIVE_PATH" | cut -f1)
        log_info "✓ Archive created: $ARCHIVE_NAME ($size)"
        return 0
    else
        log_error "✗ Archive creation failed"
        return 4
    fi
}

verify_archive() {
    log_step "Verifying archive integrity..."

    if tar -tzf "$ARCHIVE_PATH" > /dev/null 2>&1; then
        local entries=$(tar -tzf "$ARCHIVE_PATH" | wc -l)
        log_info "✓ Archive verified: $entries entries"
        return 0
    else
        log_error "✗ Archive verification failed"
        return 6
    fi
}

upload_to_storage_box() {
    if [ -z "$STORAGE_BOX" ]; then
        log_warn "Skipping Storage Box upload (not configured)"
        return 0
    fi

    log_step "Uploading to Hetzner Storage Box..."

    # Ensure remote directory exists
    ssh "$STORAGE_BOX" "mkdir -p $STORAGE_BOX_PATH" || log_warn "Could not create remote directory"

    if scp "$ARCHIVE_PATH" "${STORAGE_BOX}:${STORAGE_BOX_PATH}/"; then
        log_info "✓ Upload completed successfully"
        return 0
    else
        log_error "✗ Upload to Storage Box failed"
        return 5
    fi
}

rotate_remote_backups() {
    if [ -z "$STORAGE_BOX" ]; then
        return 0
    fi

    log_step "Rotating remote backups (retention: $BACKUP_RETENTION_DAYS days)..."

    # List backups, sort by name (which includes timestamp), keep last N
    local cleanup_cmd="cd $STORAGE_BOX_PATH && ls -t portfolio_${ENVIRONMENT}_*.tar.gz 2>/dev/null | tail -n +$((BACKUP_RETENTION_DAYS + 1)) | xargs -r rm --"

    if ssh "$STORAGE_BOX" "$cleanup_cmd" 2>/dev/null; then
        log_info "✓ Remote backup rotation completed"
    else
        log_warn "Could not rotate remote backups (may not exist yet)"
    fi
}

rotate_local_backups() {
    log_step "Rotating local backups (retention: $BACKUP_RETENTION_DAYS days)..."

    find "$LOCAL_ARCHIVE_DIR" \
        -name "portfolio_${ENVIRONMENT}_*.tar.gz" \
        -type f \
        -mtime +"$BACKUP_RETENTION_DAYS" \
        -delete 2>/dev/null || log_warn "Could not rotate local backups"

    log_info "✓ Local backup rotation completed"
}

cleanup_temp_files() {
    log_step "Cleaning up temporary files..."

    rm -rf "$BACKUP_DIR"

    log_info "✓ Cleanup completed"
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    local archive_size=$(du -h "$ARCHIVE_PATH" | cut -f1)

    echo ""
    echo "========================================="
    log_info "Backup completed successfully"
    echo "========================================="
    log_info "Environment:     $ENVIRONMENT"
    log_info "Archive:         $ARCHIVE_NAME"
    log_info "Size:            $archive_size"
    log_info "Location:        $ARCHIVE_PATH"

    if [ -n "$STORAGE_BOX" ]; then
        log_info "Remote:          ${STORAGE_BOX}:${STORAGE_BOX_PATH}/$ARCHIVE_NAME"
    fi

    log_info "Retention:       $BACKUP_RETENTION_DAYS days"
    echo "========================================="
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Starting Portfolio backup for $ENVIRONMENT"
    log_info "Timestamp: $DATE_LABEL"

    check_requirements
    check_storage_box_config
    create_backup_structure

    backup_database || exit 2
    backup_storage || exit 3
    backup_configuration

    create_archive || exit 4
    verify_archive || exit 6

    upload_to_storage_box || exit 5
    rotate_remote_backups
    rotate_local_backups

    cleanup_temp_files

    print_summary

    send_notification "SUCCESS" "Backup completed: $ARCHIVE_NAME ($(du -h "$ARCHIVE_PATH" | cut -f1))"

    log_info "All operations completed successfully"
}

main "$@"
