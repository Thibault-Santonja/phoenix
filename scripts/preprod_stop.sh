#!/usr/bin/env bash
#
# Portfolio Preproduction Environment - Stop Script
#
# Stops the preproduction Docker environment.
#
# Usage:
#   ./scripts/preprod_stop.sh
#
# What it does:
#   - Stops all running preprod containers
#   - Preserves volumes (data is kept for next start)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.preprod.yml"

# Colors
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

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    log_info "Stopping Portfolio Preproduction Environment"
    echo ""

    cd "$PROJECT_ROOT"

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_warn "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    # Stop containers (preserves volumes)
    docker-compose -f "$COMPOSE_FILE" down

    echo ""
    log_info "✓ Preproduction environment stopped"
    log_info ""
    log_info "Data preserved in Docker volumes"
    log_info "To completely remove all data, use: ./scripts/preprod_reset.sh"
    echo ""
}

main "$@"
