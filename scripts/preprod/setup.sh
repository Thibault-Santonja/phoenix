#!/usr/bin/env bash
#
# Pre-production Environment Setup Script
#
# Initializes pre-production Docker environment with all necessary configuration.
#
# Usage:
#   ./setup.sh
#
# Requirements:
#   - Docker and Docker Compose installed
#   - Sufficient disk space (~ 2GB)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

check_docker() {
    log_info "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        log_error "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose not found. Please install Docker Compose."
        log_error "Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi

    log_info "Docker $(docker --version) found"
    log_info "Docker Compose $(docker-compose --version) found"
}

generate_secrets() {
    log_info "Generating secrets..."

    local env_file="$PROJECT_ROOT/.env.preprod"

    if [ -f "$env_file" ]; then
        log_warn ".env.preprod already exists"
        read -p "Overwrite? (y/n): " overwrite
        if [ "$overwrite" != "y" ]; then
            log_info "Keeping existing .env.preprod"
            return
        fi
    fi

    local secret_key_base=$(openssl rand -base64 64 | tr -d '\n')
    local release_cookie=$(openssl rand -base64 32 | tr -d '\n' | tr -d '=' | tr '+/' '-_')

    cat > "$env_file" <<EOF
# Pre-production Environment Variables
# Generated: $(date)

# Database
DATABASE_URL=ecto://portfolio:portfolio_preprod_password@localhost:5433/portfolio_preprod

# Application
PHX_HOST=localhost
PHX_SERVER=true
PORT=4000
SECRET_KEY_BASE=$secret_key_base

# Release
RELEASE_NODE=portfolio@127.0.0.1
RELEASE_COOKIE=$release_cookie

# Storage
FILE_STORAGE_BACKEND=LocalStorage
FILE_STORAGE_BASE_PATH=/app/priv/static/uploads

# Auth
AUTH_SESSION_MAX_AGE_DAYS=30
AUTH_MAGIC_LINK_TTL_MINUTES=30
AUTH_RATE_LIMIT_MAX_REQUESTS=5
AUTH_RATE_LIMIT_WINDOW_SECONDS=300

# Email (configure for actual preprod)
# SMTP_HOST=smtp.example.com
# SMTP_PORT=587
# SMTP_USERNAME=your_username
# SMTP_PASSWORD=your_password
# FROM_EMAIL=noreply@example.com
EOF

    chmod 600 "$env_file"
    log_info "Secrets generated in .env.preprod"
}

build_images() {
    log_info "Building Docker images..."

    cd "$PROJECT_ROOT"

    if docker-compose -f docker-compose.preprod.yml build; then
        log_info "Docker images built successfully"
    else
        log_error "Failed to build Docker images"
        exit 1
    fi
}

start_services() {
    log_info "Starting services..."

    cd "$PROJECT_ROOT"

    if docker-compose -f docker-compose.preprod.yml up -d; then
        log_info "Services started successfully"
    else
        log_error "Failed to start services"
        exit 1
    fi
}

wait_for_services() {
    log_info "Waiting for services to be healthy..."

    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if docker-compose -f docker-compose.preprod.yml ps | grep -q "healthy"; then
            log_info "Services are healthy"
            return 0
        fi

        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done

    echo ""
    log_warn "Services took longer than expected to become healthy"
    log_warn "Check status with: docker-compose -f docker-compose.preprod.yml ps"
}

run_migrations() {
    log_info "Running database migrations..."

    cd "$PROJECT_ROOT"

    if docker-compose -f docker-compose.preprod.yml exec -T app /app/bin/portfolio eval "Portfolio.Release.migrate()"; then
        log_info "Migrations completed successfully"
    else
        log_error "Migrations failed"
        exit 1
    fi
}

print_summary() {
    log_info "===== Setup Complete ====="
    log_info "Pre-production environment is ready!"
    echo ""
    log_info "Services running:"
    log_info "  - Application: http://localhost:4001"
    log_info "  - PostgreSQL: localhost:5433"
    echo ""
    log_info "Useful commands:"
    log_info "  - View logs: docker-compose -f docker-compose.preprod.yml logs -f"
    log_info "  - Stop: docker-compose -f docker-compose.preprod.yml down"
    log_info "  - Restart: docker-compose -f docker-compose.preprod.yml restart"
    log_info "  - Shell: docker-compose -f docker-compose.preprod.yml exec app sh"
    log_info "=========================="
}

main() {
    log_info "Setting up pre-production environment..."

    check_docker
    generate_secrets
    build_images
    start_services
    wait_for_services
    run_migrations
    print_summary
}

main "$@"
