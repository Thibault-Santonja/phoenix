#!/usr/bin/env bash
#
# Portfolio Preproduction Environment - Reset Script
#
# Completely resets the preproduction environment by removing all containers and volumes.
# This provides a fresh start for testing.
#
# Usage:
#   ./scripts/preprod_reset.sh
#
# What it does:
#   1. Confirms destructive operation with user
#   2. Stops all containers
#   3. Removes all containers and volumes (data loss!)
#   4. Restarts environment from scratch

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.preprod.yml"

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
# Confirmation
# ============================================================================

confirm_reset() {
    echo ""
    log_warn "========================================="
    log_warn "⚠️  WARNING: DESTRUCTIVE OPERATION"
    log_warn "========================================="
    log_warn ""
    log_warn "This will PERMANENTLY DELETE:"
    log_warn "  - All preprod containers"
    log_warn "  - All preprod volumes (database + uploads)"
    log_warn "  - All preprod data"
    log_warn ""
    log_warn "This action CANNOT be undone!"
    log_warn ""
    log_warn "========================================="
    echo ""

    read -p "Are you sure you want to reset the preproduction environment? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Reset cancelled"
        exit 0
    fi

    log_info "Confirmation received, proceeding with reset..."
    echo ""
}

# ============================================================================
# Reset Operations
# ============================================================================

stop_and_remove() {
    log_info "Stopping and removing containers and volumes..."
    echo ""

    cd "$PROJECT_ROOT"

    # Stop containers and remove volumes
    if docker-compose -f "$COMPOSE_FILE" down -v; then
        echo ""
        log_info "✓ Containers and volumes removed"
    else
        echo ""
        log_error "Failed to remove containers and volumes"
        exit 1
    fi
}

restart_environment() {
    log_info "Restarting preproduction environment..."
    echo ""

    if [ -f "$SCRIPT_DIR/preprod_start.sh" ]; then
        "$SCRIPT_DIR/preprod_start.sh"
    else
        log_warn "preprod_start.sh not found"
        log_info "Manually start with: docker-compose -f docker-compose.preprod.yml up -d"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    log_warn "🗑️  Portfolio Preproduction Environment - RESET"
    echo ""

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    confirm_reset
    stop_and_remove

    echo ""
    log_info "========================================="
    log_info "Reset completed successfully"
    log_info "========================================="
    echo ""

    read -p "Do you want to restart the environment now? (y/n): " restart_confirm

    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        echo ""
        restart_environment
    else
        log_info ""
        log_info "Environment reset complete"
        log_info "Start when ready with: ./scripts/preprod_start.sh"
        echo ""
    fi
}

main "$@"
