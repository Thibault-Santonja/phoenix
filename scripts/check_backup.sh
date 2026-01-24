#!/usr/bin/env bash
#
# Portfolio Backup Monitoring Script
#
# Verifies that backups are being created successfully and are recent.
# Can be integrated with monitoring services like Healthchecks.io
#
# Usage:
#   ./check_backup.sh [environment] [max_age_hours]
#
# Arguments:
#   environment   - Environment to check (production|staging, default: production)
#   max_age_hours - Maximum acceptable backup age in hours (default: 26)
#
# Exit codes:
#   0 - Backup exists and is recent
#   1 - No backup found
#   2 - Backup too old
#   3 - Backup verification failed

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

ENVIRONMENT="${1:-production}"
MAX_AGE_HOURS="${2:-26}"  # Default: 26 hours (allows 2 hour window for daily 3am backup)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Directories
LOCAL_BACKUP_DIR="$PROJECT_ROOT/backups"

# Storage Box
STORAGE_BOX="${STORAGE_BOX:-}"
STORAGE_BOX_PATH="${STORAGE_BOX_PATH:-/backups/portfolio}"

# Healthchecks.io (optional)
HEALTHCHECK_PING_URL="${HEALTHCHECK_PING_URL:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# ============================================================================
# Healthcheck Notification
# ============================================================================

ping_healthcheck() {
    local status=$1  # "success" or "fail"

    if [ -n "$HEALTHCHECK_PING_URL" ]; then
        if [ "$status" = "success" ]; then
            curl -fsS --retry 3 "$HEALTHCHECK_PING_URL" > /dev/null 2>&1 || log_warn "Failed to ping healthcheck"
        else
            curl -fsS --retry 3 "${HEALTHCHECK_PING_URL}/fail" > /dev/null 2>&1 || log_warn "Failed to ping healthcheck"
        fi
    fi
}

# ============================================================================
# Backup Verification
# ============================================================================

find_latest_backup() {
    local location=$1  # "local" or "remote"

    if [ "$location" = "local" ]; then
        if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
            return 1
        fi

        find "$LOCAL_BACKUP_DIR" -name "portfolio_${ENVIRONMENT}_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -n \
            | tail -1 \
            | cut -d' ' -f2-
    else
        if [ -z "$STORAGE_BOX" ]; then
            return 1
        fi

        ssh "$STORAGE_BOX" "find $STORAGE_BOX_PATH -name 'portfolio_${ENVIRONMENT}_*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-" 2>/dev/null
    fi
}

get_backup_age_hours() {
    local backup_path=$1
    local location=$2  # "local" or "remote"

    local modification_time

    if [ "$location" = "local" ]; then
        modification_time=$(stat -f %m "$backup_path" 2>/dev/null || echo 0)
    else
        modification_time=$(ssh "$STORAGE_BOX" "stat -c %Y '$backup_path' 2>/dev/null || echo 0")
    fi

    local current_time=$(date +%s)
    local age_seconds=$((current_time - modification_time))
    local age_hours=$((age_seconds / 3600))

    echo "$age_hours"
}

verify_backup_integrity() {
    local backup_path=$1
    local location=$2  # "local" or "remote"

    if [ "$location" = "local" ]; then
        tar -tzf "$backup_path" > /dev/null 2>&1
    else
        # Download and verify (don't keep the file)
        local temp_file="/tmp/backup_check_$$.tar.gz"
        if scp "${STORAGE_BOX}:${backup_path}" "$temp_file" 2>/dev/null; then
            tar -tzf "$temp_file" > /dev/null 2>&1
            local result=$?
            rm -f "$temp_file"
            return $result
        else
            return 1
        fi
    fi
}

check_backup_location() {
    local location=$1  # "local" or "remote"
    local location_name=$2  # Human-readable name

    log_info "Checking $location_name backups..."

    local latest_backup=$(find_latest_backup "$location")

    if [ -z "$latest_backup" ]; then
        log_error "✗ No backup found in $location_name"
        return 1
    fi

    log_info "Latest backup: $(basename "$latest_backup")"

    # Check age
    local age_hours=$(get_backup_age_hours "$latest_backup" "$location")
    log_info "Backup age: $age_hours hours"

    if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
        log_error "✗ Backup too old (> $MAX_AGE_HOURS hours)"
        return 2
    fi

    log_info "✓ Backup age acceptable (< $MAX_AGE_HOURS hours)"

    # Verify integrity
    log_info "Verifying backup integrity..."

    if verify_backup_integrity "$latest_backup" "$location"; then
        log_info "✓ Backup integrity verified"
        return 0
    else
        log_error "✗ Backup verification failed"
        return 3
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Portfolio Backup Check"
    log_info "Environment: $ENVIRONMENT"
    log_info "Max age: $MAX_AGE_HOURS hours"
    echo ""

    local exit_code=0

    # Check local backups
    if check_backup_location "local" "local storage"; then
        log_info "✓ Local backup check passed"
    else
        log_warn "✗ Local backup check failed (code: $?)"
        exit_code=1
    fi

    echo ""

    # Check remote backups (Storage Box)
    if [ -n "$STORAGE_BOX" ]; then
        if check_backup_location "remote" "Storage Box"; then
            log_info "✓ Remote backup check passed"
        else
            log_error "✗ Remote backup check failed (code: $?)"
            exit_code=$?
        fi
    else
        log_warn "Storage Box not configured, skipping remote check"
    fi

    echo ""

    # Summary
    if [ $exit_code -eq 0 ]; then
        log_info "========================================="
        log_info "✓ All backup checks passed"
        log_info "========================================="
        ping_healthcheck "success"
    else
        log_error "========================================="
        log_error "✗ Backup checks failed (exit code: $exit_code)"
        log_error "========================================="
        ping_healthcheck "fail"
    fi

    exit $exit_code
}

main "$@"
