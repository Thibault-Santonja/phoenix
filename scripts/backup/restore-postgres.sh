#!/usr/bin/env bash
#
# PostgreSQL Restore Script
#
# Restores PostgreSQL database from a backup file.
# DANGEROUS: This will DROP the existing database and restore from backup.
#
# Usage:
#   ./restore-postgres.sh <backup_file>
#
# Example:
#   ./restore-postgres.sh backups/postgres/postgres_production_20250113_143022.sql.gz
#
# Requirements:
#   - psql available in PATH
#   - Database credentials configured via ENV vars
#   - Backup file must be gzipped SQL dump
#
# Environment Variables:
#   DATABASE_URL - PostgreSQL connection string
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "Usage: $0 <backup_file>"
    echo ""
    echo "Restore PostgreSQL database from a backup file."
    echo ""
    echo "Example:"
    echo "  $0 backups/postgres/postgres_production_20250113_143022.sql.gz"
    echo ""
    exit 1
}

check_requirements() {
    log_info "Checking requirements..."

    if ! command -v psql &> /dev/null; then
        log_error "psql not found in PATH"
        exit 1
    fi

    if ! command -v gunzip &> /dev/null; then
        log_error "gunzip not found in PATH"
        exit 1
    fi

    if [ -z "${DATABASE_URL:-}" ]; then
        log_error "DATABASE_URL environment variable not set"
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
    log_danger "========================================="
    log_danger "WARNING: DATABASE RESTORE"
    log_danger "========================================="
    log_danger "This will:"
    log_danger "  1. DROP the existing database"
    log_danger "  2. Restore from: $BACKUP_FILE"
    log_danger ""
    log_danger "ALL CURRENT DATA WILL BE LOST!"
    log_danger "========================================="
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

    if gunzip -t "$BACKUP_FILE" 2>/dev/null; then
        log_info "Backup file integrity verified"
    else
        log_error "Backup file is corrupted or not a valid gzip file"
        exit 1
    fi
}

restore_database() {
    log_info "Starting database restore..."

    # Extract and pipe directly to psql
    if gunzip -c "$BACKUP_FILE" | psql "$DATABASE_URL"; then
        log_info "Database restored successfully"
        return 0
    else
        log_error "Database restore failed"
        return 2
    fi
}

print_summary() {
    log_info "===== Restore Summary ====="
    log_info "Backup file: $BACKUP_FILE"
    log_info "Database: $(echo "$DATABASE_URL" | sed 's/:[^:]*@/@***@/')"  # Hide password
    log_info "==========================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "PostgreSQL Database Restore"

    check_requirements
    verify_backup
    confirm_restore
    restore_database || exit 2
    print_summary

    log_info "Restore completed successfully"
}

main "$@"
