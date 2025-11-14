#!/bin/bash
# Fail2ban installation script for Portfolio application
#
# This script installs and configures fail2ban for the Portfolio Phoenix application.
#
# Usage:
#   sudo ./install.sh [LOG_PATH]
#
# Arguments:
#   LOG_PATH: Optional path to Phoenix production log file
#             Default: /var/log/portfolio/production.log
#
# Author: Portfolio Security Team
# Date: 2025-11-13

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_LOG_PATH="/var/log/portfolio/production.log"
LOG_PATH="${1:-$DEFAULT_LOG_PATH}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_fail2ban_installed() {
    if ! command -v fail2ban-client &> /dev/null; then
        log_error "fail2ban is not installed"
        echo ""
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt update && sudo apt install fail2ban"
        echo "  CentOS/RHEL:   sudo yum install epel-release && sudo yum install fail2ban"
        exit 1
    fi
    log_info "fail2ban is installed"
}

create_log_directory() {
    local log_dir=$(dirname "$LOG_PATH")

    if [ ! -d "$log_dir" ]; then
        log_warn "Log directory $log_dir does not exist, creating it..."
        mkdir -p "$log_dir"
        chmod 755 "$log_dir"
        log_info "Created log directory: $log_dir"
    else
        log_info "Log directory exists: $log_dir"
    fi
}

install_filter() {
    local filter_src="$SCRIPT_DIR/filter.d/portfolio-rate-limit.conf"
    local filter_dst="/etc/fail2ban/filter.d/portfolio-rate-limit.conf"

    if [ ! -f "$filter_src" ]; then
        log_error "Filter file not found: $filter_src"
        exit 1
    fi

    log_info "Installing filter: $filter_dst"
    cp "$filter_src" "$filter_dst"
    chmod 644 "$filter_dst"
    log_info "Filter installed successfully"
}

install_jail() {
    local jail_src="$SCRIPT_DIR/jail.d/portfolio.conf"
    local jail_dst="/etc/fail2ban/jail.d/portfolio.conf"

    if [ ! -f "$jail_src" ]; then
        log_error "Jail file not found: $jail_src"
        exit 1
    fi

    log_info "Installing jail: $jail_dst"

    # Create temporary file with updated log path
    local temp_jail=$(mktemp)
    sed "s|logpath = /var/log/portfolio/\*.log|logpath = $LOG_PATH|g" "$jail_src" > "$temp_jail"

    cp "$temp_jail" "$jail_dst"
    chmod 644 "$jail_dst"
    rm "$temp_jail"

    log_info "Jail installed successfully (logpath: $LOG_PATH)"
}

test_configuration() {
    log_info "Testing fail2ban configuration..."

    if fail2ban-client -t; then
        log_info "Configuration test passed"
    else
        log_error "Configuration test failed"
        exit 1
    fi
}

restart_fail2ban() {
    log_info "Restarting fail2ban service..."

    systemctl restart fail2ban

    if systemctl is-active --quiet fail2ban; then
        log_info "fail2ban restarted successfully"
    else
        log_error "fail2ban failed to start"
        exit 1
    fi
}

verify_jail() {
    log_info "Verifying portfolio jail is active..."

    sleep 2  # Give fail2ban time to load the jail

    if fail2ban-client status | grep -q "portfolio-rate-limit"; then
        log_info "portfolio-rate-limit jail is active"
        echo ""
        fail2ban-client status portfolio-rate-limit
    else
        log_error "portfolio-rate-limit jail is not active"
        log_warn "Check /var/log/fail2ban.log for errors"
        exit 1
    fi
}

test_filter() {
    log_info "Testing filter against sample log entry..."

    local sample_log="[warning] Rate limit exceeded for login_request identifier: 192.168.1.100 retry_after_seconds: 300"

    if echo "$sample_log" | fail2ban-regex - /etc/fail2ban/filter.d/portfolio-rate-limit.conf | grep -q "1 hit(s)"; then
        log_info "Filter test passed - pattern matches correctly"
    else
        log_warn "Filter test returned unexpected results"
        log_warn "Manually verify with: fail2ban-regex $LOG_PATH /etc/fail2ban/filter.d/portfolio-rate-limit.conf"
    fi
}

show_next_steps() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Installation completed successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Verify Phoenix logs are being written to: $LOG_PATH"
    echo "   Test with: tail -f $LOG_PATH"
    echo ""
    echo "2. Monitor fail2ban status:"
    echo "   sudo fail2ban-client status portfolio-rate-limit"
    echo ""
    echo "3. View fail2ban logs:"
    echo "   sudo tail -f /var/log/fail2ban.log"
    echo ""
    echo "4. Test filter manually (once logs exist):"
    echo "   sudo fail2ban-regex $LOG_PATH /etc/fail2ban/filter.d/portfolio-rate-limit.conf"
    echo ""
    echo "5. Manual ban/unban commands:"
    echo "   sudo fail2ban-client set portfolio-rate-limit banip 192.168.1.100"
    echo "   sudo fail2ban-client set portfolio-rate-limit unbanip 192.168.1.100"
    echo ""
    echo "For more information, see: config/fail2ban/README.md"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Portfolio fail2ban Installation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    check_root
    check_fail2ban_installed
    create_log_directory
    install_filter
    install_jail
    test_configuration
    restart_fail2ban
    verify_jail
    test_filter
    show_next_steps
}

# Run main function
main "$@"
