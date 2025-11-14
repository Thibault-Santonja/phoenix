# Fail2ban Deployment Guide

This guide provides step-by-step instructions for deploying fail2ban protection for the Portfolio application in various environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local/VM Deployment](#localvm-deployment)
3. [Docker/Kamal Deployment](#dockerkamal-deployment)
4. [Verification](#verification)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- Linux-based server (Ubuntu 20.04+, Debian 10+, CentOS 7+, or similar)
- Root or sudo access
- fail2ban 0.11.0 or higher
- iptables or nftables

### Application Requirements

- Phoenix application must log to a file (not just console/stdout)
- Log file must be readable by fail2ban user
- Rate limiting must be enabled in the application

## Local/VM Deployment

### Step 1: Install fail2ban

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install fail2ban

# CentOS/RHEL
sudo yum install epel-release
sudo yum install fail2ban

# Start and enable service
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
```

### Step 2: Configure Phoenix Logging

Ensure Phoenix logs to a file. In `config/runtime.exs` or `config/prod.exs`:

```elixir
# Option 1: Using default logger with file backend
config :logger, :default_handler,
  config: [
    file: ~c"/var/log/portfolio/production.log",
    filesync_repeat_interval: 5000,
    max_no_bytes: 10_000_000,
    max_no_files: 5
  ]

# Option 2: Using LoggerFileBackend (if installed)
config :logger, backends: [:console, {LoggerFileBackend, :file_log}]

config :logger, :file_log,
  path: "/var/log/portfolio/production.log",
  level: :warning,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :action, :identifier]
```

Create log directory:

```bash
sudo mkdir -p /var/log/portfolio
sudo chown portfolio:portfolio /var/log/portfolio
sudo chmod 755 /var/log/portfolio
```

### Step 3: Install fail2ban Configuration

Using the automated installer:

```bash
cd /path/to/portfolio
sudo ./config/fail2ban/install.sh /var/log/portfolio/production.log
```

Or manually:

```bash
# Copy filter
sudo cp config/fail2ban/filter.d/portfolio-rate-limit.conf \
  /etc/fail2ban/filter.d/

# Copy and configure jail
sudo cp config/fail2ban/jail.d/portfolio.conf \
  /etc/fail2ban/jail.d/

# Edit jail to set correct log path
sudo nano /etc/fail2ban/jail.d/portfolio.conf
# Update: logpath = /var/log/portfolio/production.log

# Test configuration
sudo fail2ban-client -t

# Restart fail2ban
sudo systemctl restart fail2ban
```

### Step 4: Verify Installation

```bash
# Check jail is loaded
sudo fail2ban-client status
# Should show "portfolio-rate-limit" in the list

# Get detailed status
sudo fail2ban-client status portfolio-rate-limit

# Test filter
sudo fail2ban-regex /var/log/portfolio/production.log \
  /etc/fail2ban/filter.d/portfolio-rate-limit.conf
```

## Docker/Kamal Deployment

### Approach 1: Host-Based fail2ban (Recommended)

Run fail2ban on the host machine and monitor Docker logs.

#### Configure Docker Logging

In your Kamal configuration or docker-compose:

```yaml
# config/deploy.yml (Kamal)
service: portfolio

accessories:
  logging:
    volumes:
      - /var/log/portfolio:/app/log

env:
  LOG_PATH: /app/log/production.log
```

Or in Docker command:

```bash
docker run -d \
  --name portfolio \
  -v /var/log/portfolio:/app/log \
  -e LOG_PATH=/app/log/production.log \
  portfolio:latest
```

#### Configure Phoenix for File Logging

```elixir
# config/runtime.exs
log_path = System.get_env("LOG_PATH", "/app/log/production.log")

config :logger, :default_handler,
  config: [
    file: String.to_charlist(log_path),
    filesync_repeat_interval: 5000
  ]
```

#### Install fail2ban on Host

```bash
# On the Docker host machine
sudo apt install fail2ban

# Install Portfolio fail2ban config
sudo ./config/fail2ban/install.sh /var/log/portfolio/production.log

# Verify
sudo fail2ban-client status portfolio-rate-limit
```

### Approach 2: Syslog forwarding

Forward Docker logs to syslog, then monitor syslog with fail2ban.

```bash
# Configure Docker to use syslog driver
docker run -d \
  --name portfolio \
  --log-driver=syslog \
  --log-opt syslog-address=udp://localhost:514 \
  --log-opt tag="portfolio" \
  portfolio:latest
```

Update jail to monitor syslog:

```ini
# /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
logpath = /var/log/syslog
```

Update filter for syslog format:

```ini
# /etc/fail2ban/filter.d/portfolio-rate-limit.conf
[Definition]
failregex = ^.*portfolio.*Rate limit exceeded.*identifier:\s*<HOST>.*$
```

### Approach 3: fail2ban in Container (Advanced)

Run fail2ban inside a dedicated container (not recommended for production).

```dockerfile
# Dockerfile.fail2ban
FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y fail2ban iptables && \
    rm -rf /var/lib/apt/lists/*

COPY config/fail2ban/filter.d/portfolio-rate-limit.conf /etc/fail2ban/filter.d/
COPY config/fail2ban/jail.d/portfolio.conf /etc/fail2ban/jail.d/

CMD ["fail2ban-server", "-f"]
```

```yaml
# docker-compose.yml
services:
  app:
    image: portfolio:latest
    volumes:
      - logs:/var/log/portfolio
  
  fail2ban:
    build:
      context: .
      dockerfile: Dockerfile.fail2ban
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - logs:/var/log/portfolio:ro
    depends_on:
      - app

volumes:
  logs:
```

## Verification

### 1. Check Service Status

```bash
# fail2ban service
sudo systemctl status fail2ban

# Portfolio jail
sudo fail2ban-client status portfolio-rate-limit
```

### 2. Test Log Pattern Matching

Create a test log entry:

```bash
echo "[warning] Rate limit exceeded for login_request identifier: 192.168.1.100 retry_after_seconds: 300" | \
  sudo tee -a /var/log/portfolio/production.log

# Test filter
sudo fail2ban-regex /var/log/portfolio/production.log \
  /etc/fail2ban/filter.d/portfolio-rate-limit.conf
```

Expected output: "Failregex: 1 hit(s)"

### 3. Simulate Rate Limit

From another machine:

```bash
# Trigger rate limits
for i in {1..25}; do
  curl -X POST https://your-server.com/auth/magic \
    -d "email=test@example.com" \
    -H "Content-Type: application/x-www-form-urlencoded"
  sleep 1
done
```

Check if IP was banned:

```bash
sudo fail2ban-client status portfolio-rate-limit
# Look for the test IP in "Currently banned"
```

### 4. Test Manual Ban/Unban

```bash
# Ban test IP
sudo fail2ban-client set portfolio-rate-limit banip 192.168.1.100

# Verify ban
sudo iptables -L -n | grep 192.168.1.100

# Unban
sudo fail2ban-client set portfolio-rate-limit unbanip 192.168.1.100
```

## Monitoring

### Real-time Monitoring

```bash
# Watch fail2ban log
sudo tail -f /var/log/fail2ban.log

# Watch application log
sudo tail -f /var/log/portfolio/production.log | grep "Rate limit"

# Watch banned IPs
watch -n 5 'sudo fail2ban-client status portfolio-rate-limit'
```

### Metrics and Alerts

#### Prometheus Integration

Export fail2ban metrics for Prometheus:

```bash
# Install fail2ban-exporter
wget https://github.com/jangrewe/prometheus-fail2ban-exporter/releases/download/v0.1.0/fail2ban_exporter
sudo mv fail2ban_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/fail2ban_exporter

# Run as service
sudo systemctl enable --now fail2ban-exporter
```

Add to Prometheus config:

```yaml
scrape_configs:
  - job_name: 'fail2ban'
    static_configs:
      - targets: ['localhost:9191']
```

#### Email Notifications

Configure email alerts in jail:

```ini
# /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
action = iptables-multiport[name=portfolio, port="http,https", protocol=tcp]
         sendmail-whois[name=portfolio, dest=admin@example.com, sender=fail2ban@example.com]

# Configure SMTP
# In /etc/fail2ban/action.d/sendmail-common.conf
[DEFAULT]
sender = fail2ban@example.com
dest = admin@example.com
```

#### Slack/Discord Notifications

Custom action for Slack:

```ini
# /etc/fail2ban/action.d/slack-notify.conf
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = curl -X POST <slack_webhook_url> -H 'Content-Type: application/json' -d '{"text":"fail2ban: Banned <ip> from portfolio-rate-limit"}'
actionunban = curl -X POST <slack_webhook_url> -H 'Content-Type: application/json' -d '{"text":"fail2ban: Unbanned <ip> from portfolio-rate-limit"}'
```

Use in jail:

```ini
[portfolio-rate-limit]
action = iptables-multiport[name=portfolio, port="http,https", protocol=tcp]
         slack-notify[slack_webhook_url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"]
```

## Troubleshooting

### Jail Not Starting

**Problem**: Portfolio jail doesn't appear in `fail2ban-client status`

**Solutions**:

```bash
# Check configuration syntax
sudo fail2ban-client -t

# Check fail2ban logs
sudo tail -100 /var/log/fail2ban.log | grep -i portfolio

# Verify files exist
ls -l /etc/fail2ban/filter.d/portfolio-rate-limit.conf
ls -l /etc/fail2ban/jail.d/portfolio.conf

# Check for syntax errors
sudo fail2ban-client -vvv start
```

### Filter Not Matching

**Problem**: `fail2ban-regex` shows 0 hits

**Solutions**:

```bash
# Test with verbose output
sudo fail2ban-regex /var/log/portfolio/production.log \
  /etc/fail2ban/filter.d/portfolio-rate-limit.conf \
  --print-all-matched \
  --print-all-missed

# Verify log format matches filter
sudo tail /var/log/portfolio/production.log | grep "Rate limit"

# Check log file permissions
ls -l /var/log/portfolio/production.log
# Should be readable by fail2ban user

# Grant access if needed
sudo chmod 644 /var/log/portfolio/production.log
```

### Logs Not Being Written

**Problem**: Application logs aren't appearing in the log file

**Solutions**:

```bash
# Verify Phoenix logger configuration
# In config/runtime.exs or config/prod.exs

# Check directory exists and is writable
ls -ld /var/log/portfolio

# Check disk space
df -h /var/log

# Monitor application startup
sudo journalctl -u portfolio -f

# Test log writing
iex -S mix phx.server
# Then trigger a rate limit and check logs
```

### False Positives

**Problem**: Legitimate users getting banned

**Solutions**:

```ini
# Increase thresholds in /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
maxretry = 30      # Increase from 20
findtime = 900     # Increase to 15 minutes
bantime = 1800     # Reduce to 30 minutes

# Whitelist trusted IPs
ignoreip = 127.0.0.1/8 ::1
           192.168.0.0/16
           10.0.0.0/8
           your.trusted.ip.address
```

### High Memory Usage

**Problem**: fail2ban consuming excessive memory

**Solutions**:

```ini
# Limit log processing in /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
maxlines = 10000   # Limit lines to process

# Use logrotate for application logs
# /etc/logrotate.d/portfolio
/var/log/portfolio/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

## Security Considerations

### Whitelist Critical IPs

Always whitelist monitoring systems, load balancers, and admin IPs:

```ini
[portfolio-rate-limit]
ignoreip = 127.0.0.1/8 ::1
           # Your office
           203.0.113.0/24
           # Monitoring (e.g., UptimeRobot)
           46.137.190.0/24
           # Load balancer
           10.0.1.0/24
```

### Persistent Bans

For repeated offenders, use persistent bans:

```bash
# View repeat offenders
sudo fail2ban-client get portfolio-rate-limit banip

# Add permanent iptables rule
sudo iptables -I INPUT -s 203.0.113.100 -j DROP
sudo iptables-save > /etc/iptables/rules.v4
```

### Rate Limit Before Application

For best performance, rate limit at multiple layers:

1. **Cloudflare/CDN**: DDoS protection, bot detection
2. **fail2ban**: Network firewall, persistent bans
3. **Nginx/Traefik**: Request rate limiting
4. **Application**: Business logic rate limiting

### Backup Configuration

```bash
# Backup fail2ban config
sudo tar czf fail2ban-config-backup-$(date +%Y%m%d).tar.gz \
  /etc/fail2ban/jail.d/portfolio.conf \
  /etc/fail2ban/filter.d/portfolio-rate-limit.conf

# Store backup securely
cp fail2ban-config-backup-*.tar.gz ~/backups/
```

## Maintenance

### Log Rotation

Ensure logs are rotated to prevent disk space issues:

```bash
# /etc/logrotate.d/portfolio
/var/log/portfolio/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 portfolio portfolio
    sharedscripts
    postrotate
        systemctl reload fail2ban > /dev/null 2>&1 || true
    endscript
}
```

### Regular Audits

```bash
# Monthly: Review banned IPs
sudo fail2ban-client status portfolio-rate-limit

# Weekly: Check for false positives in logs
sudo grep "Rate limit exceeded" /var/log/portfolio/production.log | \
  awk '{print $NF}' | sort | uniq -c | sort -rn

# Daily: Monitor fail2ban health
sudo systemctl status fail2ban
```

## References

- [fail2ban Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [Portfolio ADR 023: Rate Limiting](../../docs/adr/023_rate_limiting.md)
- [Portfolio ADR 050: Security Layered Defense](../../docs/adr/050_security_layered_defense.md)
- [Installation Guide](README.md)

Last updated: 2025-11-13
