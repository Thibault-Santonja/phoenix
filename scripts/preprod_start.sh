#!/usr/bin/env bash
#
# Portfolio Preproduction Environment - Start Script
#
# Starts the preproduction Docker environment for local testing.
# This provides a production-like environment for validating deployments.
#
# Usage:
#   ./scripts/preprod_start.sh
#
# Requirements:
#   - Docker installed and running
#   - docker-compose available
#
# What it does:
#   1. Checks Docker is running
#   2. Builds the application image
#   3. Starts PostgreSQL and Application containers
#   4. Waits for services to be healthy
#   5. Runs database migrations
#   6. Displays access information

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
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# ============================================================================
# Validation
# ============================================================================

check_docker() {
    log_step "Checking Docker..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker Desktop."
        exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi

    log_success "Docker is running"
}

check_compose_file() {
    log_step "Checking configuration..."

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    log_success "Configuration found"
}

# ============================================================================
# Docker Operations
# ============================================================================

build_images() {
    log_step "Building Docker images..."
    echo ""

    if docker-compose -f "$COMPOSE_FILE" build; then
        echo ""
        log_success "Images built successfully"
    else
        echo ""
        log_error "Image build failed"
        exit 1
    fi
}

start_services() {
    log_step "Starting services..."
    echo ""

    if docker-compose -f "$COMPOSE_FILE" up -d; then
        echo ""
        log_success "Services started"
    else
        echo ""
        log_error "Failed to start services"
        exit 1
    fi
}

wait_for_database() {
    log_step "Waiting for PostgreSQL to be ready..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U portfolio > /dev/null 2>&1; then
            log_success "PostgreSQL is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done

    echo ""
    log_error "PostgreSQL failed to start within timeout"
    return 1
}

wait_for_app() {
    log_step "Waiting for application to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf http://localhost:4001/health > /dev/null 2>&1; then
            log_success "Application is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done

    echo ""
    log_warn "Application health check not responding (may still be starting)"
    log_warn "Check logs with: docker-compose -f docker-compose.preprod.yml logs -f app"
    return 0
}

run_migrations() {
    log_step "Running database migrations..."
    echo ""

    # Try to run migrations using the release binary
    if docker-compose -f "$COMPOSE_FILE" exec -T app /app/bin/portfolio eval "Portfolio.Release.migrate()" 2>&1; then
        echo ""
        log_success "Migrations completed"
    else
        echo ""
        log_warn "Could not run migrations automatically"
        log_warn "You may need to run them manually:"
        log_warn "  docker-compose -f docker-compose.preprod.yml exec app /app/bin/portfolio eval \"Portfolio.Release.migrate()\""
    fi
}

# ============================================================================
# Information Display
# ============================================================================

show_status() {
    echo ""
    echo "========================================="
    log_info "Preproduction Environment Status"
    echo "========================================="
    echo ""

    docker-compose -f "$COMPOSE_FILE" ps

    echo ""
}

show_usage_info() {
    echo "========================================="
    log_info "Access Information"
    echo "========================================="
    echo ""
    echo -e "${CYAN}Application:${NC}"
    echo "  URL:      http://localhost:4001"
    echo "  Health:   http://localhost:4001/health"
    echo ""
    echo -e "${CYAN}Database:${NC}"
    echo "  Host:     localhost"
    echo "  Port:     5433"
    echo "  User:     portfolio"
    echo "  Password: portfolio_preprod_password"
    echo "  Database: portfolio_preprod"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  Logs (all):       docker-compose -f docker-compose.preprod.yml logs -f"
    echo "  Logs (app):       docker-compose -f docker-compose.preprod.yml logs -f app"
    echo "  Logs (db):        docker-compose -f docker-compose.preprod.yml logs -f postgres"
    echo "  Shell (app):      docker-compose -f docker-compose.preprod.yml exec app sh"
    echo "  Shell (db):       docker-compose -f docker-compose.preprod.yml exec postgres psql -U portfolio portfolio_preprod"
    echo "  Stop:             ./scripts/preprod_stop.sh"
    echo "  Reset:            ./scripts/preprod_reset.sh"
    echo "  Restart:          docker-compose -f docker-compose.preprod.yml restart"
    echo ""
    echo "========================================="
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "🚀 Starting Portfolio Preproduction Environment"
    echo ""

    cd "$PROJECT_ROOT"

    check_docker
    check_compose_file
    build_images
    start_services
    wait_for_database
    run_migrations
    wait_for_app

    show_status
    show_usage_info

    log_success "Preproduction environment started successfully!"
    echo ""
}

main "$@"
