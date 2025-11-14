#!/usr/bin/env bash
#
# Pre-production Deployment Script
#
# Deploys new version to pre-production environment with zero-downtime.
#
# Usage:
#   ./deploy.sh [--no-build]
#
# Options:
#   --no-build    Skip Docker image rebuild (use existing image)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NO_BUILD=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --no-build)
            NO_BUILD=true
            shift
            ;;
    esac
done

create_backup() {
    log_info "Creating pre-deployment backup..."

    if [ -f "$SCRIPT_DIR/../backup/backup-postgres.sh" ]; then
        DATABASE_URL="ecto://portfolio:portfolio_preprod_password@localhost:5433/portfolio_preprod" \
            BACKUP_DIR="$PROJECT_ROOT/backups/preprod" \
            "$SCRIPT_DIR/../backup/backup-postgres.sh" preprod || log_warn "Backup failed"
    else
        log_warn "Backup script not found, skipping backup"
    fi
}

build_new_image() {
    if [ "$NO_BUILD" = true ]; then
        log_info "Skipping build (--no-build flag)"
        return
    fi

    log_info "Building new Docker image..."

    cd "$PROJECT_ROOT"

    if docker-compose -f docker-compose.preprod.yml build; then
        log_info "New image built successfully"
    else
        log_error "Failed to build new image"
        exit 1
    fi
}

run_migrations() {
    log_info "Running database migrations..."

    cd "$PROJECT_ROOT"

    # Run migrations on temporary container
    if docker-compose -f docker-compose.preprod.yml run --rm app /app/bin/portfolio eval "Portfolio.Release.migrate()"; then
        log_info "Migrations completed"
    else
        log_error "Migrations failed"
        exit 1
    fi
}

deploy_new_version() {
    log_info "Deploying new version..."

    cd "$PROJECT_ROOT"

    # Recreate app container with new image
    if docker-compose -f docker-compose.preprod.yml up -d --force-recreate --no-deps app; then
        log_info "New version deployed"
    else
        log_error "Deployment failed"
        exit 1
    fi
}

wait_for_health() {
    log_info "Waiting for application to be healthy..."

    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -sf http://localhost:4001/health > /dev/null 2>&1; then
            log_info "Application is healthy"
            return 0
        fi

        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done

    echo ""
    log_error "Application failed to become healthy"
    log_error "Check logs with: docker-compose -f docker-compose.preprod.yml logs app"
    exit 1
}

cleanup_old_images() {
    log_info "Cleaning up old Docker images..."

    docker image prune -f > /dev/null 2>&1 || true
    log_info "Cleanup completed"
}

print_summary() {
    log_info "===== Deployment Complete ====="
    log_info "New version deployed successfully!"
    echo ""
    log_info "Application: http://localhost:4001"
    log_info "Version: $(git rev-parse --short HEAD)"
    log_info "Deployed at: $(date)"
    echo ""
    log_info "Monitor with: docker-compose -f docker-compose.preprod.yml logs -f app"
    log_info "============================="
}

main() {
    log_info "Starting pre-production deployment..."

    create_backup
    build_new_image
    run_migrations
    deploy_new_version
    wait_for_health
    cleanup_old_images
    print_summary
}

main "$@"
