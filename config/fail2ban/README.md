# Fail2Ban Configuration for Portfolio

This directory contains fail2ban configuration files to protect the Portfolio application against brute force attacks and rate limit abuse.

## Overview

Fail2ban monitors application logs and automatically bans IP addresses that exceed rate limits by adding firewall rules (iptables). This provides an additional layer of security at the network level, preventing malicious clients from even reaching the application.

## Architecture

```
┌─────────────────┐
│   Attacker      │
└────────┬────────┘
         │ HTTP Request
         ▼
┌─────────────────┐
│   iptables      │ ◄─── fail2ban monitors logs and updates rules
│   (firewall)    │
└────────┬────────┘
         │ Allowed requests only
         ▼
┌─────────────────┐
│   Phoenix App   │
│   Rate Limiter  │
└─────────────────┘
```

## Files

- `filter.d/portfolio-rate-limit.conf`: Log pattern matching filter
- `jail.d/portfolio.conf`: Jail configuration (ban duration, thresholds)
- `README.md`: This documentation file

## Installation

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install fail2ban

# CentOS/RHEL
sudo yum install epel-release
sudo yum install fail2ban

# Verify installation
sudo systemctl status fail2ban
```

### Setup

1. Copy configuration files:

```bash
# Copy filter
sudo cp config/fail2ban/filter.d/portfolio-rate-limit.conf /etc/fail2ban/filter.d/

# Copy jail configuration
sudo cp config/fail2ban/jail.d/portfolio.conf /etc/fail2ban/jail.d/
```

2. Adjust log path in `/etc/fail2ban/jail.d/portfolio.conf`:

```ini
logpath = /var/log/portfolio/production.log  # Update to your actual log path
```

3. Restart fail2ban:

```bash
sudo systemctl restart fail2ban
```

4. Verify jail is active:

```bash
sudo fail2ban-client status
# Should show "portfolio-rate-limit" in the jail list

sudo fail2ban-client status portfolio-rate-limit
# Shows detailed status including banned IPs
```

## Configuration

### Current Settings

- **maxretry**: 20 violations
- **findtime**: 600 seconds (10 minutes)
- **bantime**: 3600 seconds (1 hour)

This means: If an IP triggers rate limits 20 times within 10 minutes, it will be banned for 1 hour.

### Customization

Edit `/etc/fail2ban/jail.d/portfolio.conf` to adjust:

```ini
# Ban for 24 hours instead of 1 hour
bantime = 86400

# Ban after 10 violations instead of 20
maxretry = 10

# Monitor 5 minutes instead of 10
findtime = 300
```

After changes:
```bash
sudo systemctl restart fail2ban
```

## Testing

### Test Filter Pattern

Test if the filter correctly matches your logs:

```bash
# Test with actual log file
sudo fail2ban-regex /var/log/portfolio/production.log /etc/fail2ban/filter.d/portfolio-rate-limit.conf

# Test with sample log entry
echo "[warning] Rate limit exceeded for login_request identifier: 192.168.1.100 retry_after_seconds: 300" | \
  sudo fail2ban-regex - /etc/fail2ban/filter.d/portfolio-rate-limit.conf
```

Expected output should show "Failregex: X hit(s)" with X > 0.

### Simulate Attack

1. Generate rate limit violations (from test machine):

```bash
# Trigger rate limits by making many requests
for i in {1..25}; do
  curl http://your-server/login -d "email=test@example.com"
  sleep 1
done
```

2. Check if IP was banned:

```bash
sudo fail2ban-client status portfolio-rate-limit
# Look for your test IP in "Currently banned"

# Check iptables rules
sudo iptables -L -n | grep "your-test-ip"
```

### Manual Actions

```bash
# Ban an IP manually
sudo fail2ban-client set portfolio-rate-limit banip 192.168.1.100

# Unban an IP
sudo fail2ban-client set portfolio-rate-limit unbanip 192.168.1.100

# Check banned IPs
sudo fail2ban-client get portfolio-rate-limit banip
```

## Log Configuration

Ensure Phoenix logs to a file that fail2ban can monitor.

### Production Configuration

In `config/prod.exs` or `config/runtime.exs`:

```elixir
config :logger, :default_handler,
  config: [
    file: ~c"/var/log/portfolio/production.log",
    filesync_repeat_interval: 5000,
    file_check: 5000,
    max_no_bytes: 10_000_000,
    max_no_files: 5,
    compress_on_rotate: true
  ]

# Or using Logger.Backends.File
config :logger, backends: [:console, {LoggerFileBackend, :file_log}]

config :logger, :file_log,
  path: "/var/log/portfolio/production.log",
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

### Docker/Kamal Deployment

When using Docker, ensure logs are mounted to host:

```yaml
# In kamal config or docker-compose.yml
volumes:
  - /var/log/portfolio:/app/log
```

### Systemd/journald

If using systemd, configure journald to write to file:

```bash
# /etc/systemd/journald.conf
Storage=persistent
ForwardToSyslog=yes
```

Then update jail logpath:
```ini
logpath = /var/log/syslog
```

## Monitoring

### Check Status

```bash
# Overall fail2ban status
sudo fail2ban-client status

# Portfolio jail specific status
sudo fail2ban-client status portfolio-rate-limit

# View recent bans
sudo fail2ban-client get portfolio-rate-limit banip

# View fail2ban logs
sudo tail -f /var/log/fail2ban.log
```

### Email Notifications

Configure email alerts when IPs are banned:

```ini
# In /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
action = iptables-multiport[name=portfolio, port="http,https", protocol=tcp]
         sendmail-whois[name=portfolio, dest=admin@example.com, sender=fail2ban@example.com]
```

## Troubleshooting

### Jail Not Starting

```bash
# Check configuration syntax
sudo fail2ban-client -t

# Check fail2ban logs
sudo tail -f /var/log/fail2ban.log

# Verify filter file exists
ls -l /etc/fail2ban/filter.d/portfolio-rate-limit.conf

# Verify jail file exists
ls -l /etc/fail2ban/jail.d/portfolio.conf
```

### Filter Not Matching

```bash
# Test filter against log
sudo fail2ban-regex /var/log/portfolio/production.log \
  /etc/fail2ban/filter.d/portfolio-rate-limit.conf --print-all-matched

# Check log file permissions
ls -l /var/log/portfolio/production.log
# fail2ban user must have read permission

# Grant read access if needed
sudo chmod 644 /var/log/portfolio/production.log
```

### No Logs Found

```bash
# Verify log path
sudo fail2ban-client get portfolio-rate-limit logpath

# Check if log file exists and has content
sudo tail /var/log/portfolio/production.log

# Check Phoenix logger configuration
# Ensure logger writes to file in production
```

## Security Considerations

### Whitelist Trusted IPs

To prevent accidentally banning yourself or trusted IPs:

```ini
# In /etc/fail2ban/jail.d/portfolio.conf
[portfolio-rate-limit]
ignoreip = 127.0.0.1/8 ::1
           192.168.1.0/24    # Your office network
           10.0.0.0/8        # Internal network
```

### Rate Limit vs fail2ban

The application has two layers of rate limiting:

1. **Application Level** (Hammer): Fast, in-memory, returns 429 with retry-after
   - Prevents resource exhaustion
   - User-friendly error messages
   - Configurable per-action limits

2. **Network Level** (fail2ban): Persistent, firewall-based, blocks at IP level
   - Prevents repeated attacks
   - Reduces server load
   - Protects against distributed attacks

Both layers work together for defense in depth.

### Persistent Bans

For serious offenders, use permanent bans:

```bash
# Add to iptables permanently
sudo iptables -I INPUT -s 203.0.113.0 -j DROP
sudo iptables-save > /etc/iptables/rules.v4
```

## Integration with Application

The application logs rate limit violations in this format:

```
[warning] Rate limit exceeded for login_request identifier: 192.168.1.100 retry_after_seconds: 300
```

This is logged by `PortfolioWeb.Plugs.RateLimiterPlug` module when rate limits are exceeded.

## Performance Impact

fail2ban is lightweight and has minimal performance impact:

- Runs as separate process, not in application
- Monitors logs asynchronously
- Updates iptables rules efficiently
- No impact on successful requests

Typical resource usage:
- Memory: 10-20 MB
- CPU: < 1% average

## References

- [fail2ban official documentation](https://www.fail2ban.org/)
- [fail2ban GitHub](https://github.com/fail2ban/fail2ban)
- [Portfolio ADR 023: Rate Limiting](../../docs/adr/023_rate_limiting.md)
- [Portfolio ADR 050: Security Layered Defense](../../docs/adr/050_security_layered_defense.md)

## Support

For issues or questions:
1. Check fail2ban logs: `/var/log/fail2ban.log`
2. Test filter manually with `fail2ban-regex`
3. Verify Phoenix logs are being written
4. Review this documentation

Last updated: 2025-11-13
