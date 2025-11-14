# Portfolio Scripts

This directory contains operational scripts for backup, restoration, and monitoring.

## Backup Scripts

### backup.sh

Unified backup script that creates comprehensive backups of PostgreSQL database, photos, and configuration.

**Usage:**
```bash
./scripts/backup.sh [environment]
```

**Environment variables:**
```bash
DATABASE_URL=ecto://user:password@localhost/portfolio_prod
APP_STORAGE=/app/priv/static/uploads
STORAGE_BOX=u123456@u123456.your-storagebox.de
STORAGE_BOX_PATH=/backups/portfolio
BACKUP_RETENTION_DAYS=7
NOTIFICATION_WEBHOOK=https://hooks.slack.com/your-webhook  # Optional
```

**Example:**
```bash
# Production backup
DATABASE_URL=$DATABASE_URL \
STORAGE_BOX=u123456@u123456.your-storagebox.de \
./scripts/backup.sh production

# Staging backup
./scripts/backup.sh staging
```

**Output:**
- Creates compressed archive: `portfolio_<env>_<timestamp>.tar.gz`
- Uploads to Hetzner Storage Box (if configured)
- Rotates old backups (keeps last 7 by default)
- Logs to stdout/stderr

---

### restore.sh

Restores PostgreSQL database, photos, and configuration from a backup archive.

**Usage:**
```bash
./scripts/restore.sh <backup_archive.tar.gz> [environment]
```

**Examples:**
```bash
# Restore from local file
./scripts/restore.sh backups/portfolio_production_20251115_030000.tar.gz

# Restore from Storage Box (auto-downloads)
STORAGE_BOX=u123456@u123456.your-storagebox.de \
./scripts/restore.sh portfolio_production_20251115_030000.tar.gz

# Restore to staging environment
./scripts/restore.sh backup.tar.gz staging
```

**Warning:** This is a **destructive operation**. It will:
1. DROP and recreate the database
2. DELETE all current files in storage
3. Restore from backup

Always confirm before proceeding.

---

### check_backup.sh

Monitoring script that verifies backups are being created successfully and are recent.

**Usage:**
```bash
./scripts/check_backup.sh [environment] [max_age_hours]
```

**Examples:**
```bash
# Check production backups (default: max 26 hours old)
./scripts/check_backup.sh production

# Check with custom max age
./scripts/check_backup.sh production 12

# With Healthchecks.io monitoring
HEALTHCHECK_PING_URL=https://hc-ping.com/your-uuid \
./scripts/check_backup.sh production
```

**Exit codes:**
- 0: Backup exists and is recent
- 1: No backup found
- 2: Backup too old
- 3: Backup verification failed

---

## Setup

### 1. Configure Storage Box SSH

Generate SSH key and copy to Storage Box:

```bash
# Generate key
ssh-keygen -t ed25519 -f ~/.ssh/storagebox_backup -N ""

# Copy to Storage Box
ssh-copy-id -i ~/.ssh/storagebox_backup.pub u123456@u123456.your-storagebox.de

# Test connection
ssh -i ~/.ssh/storagebox_backup u123456@u123456.your-storagebox.de

# Create backup directory
ssh u123456@u123456.your-storagebox.de "mkdir -p /backups/portfolio"
```

Add to `~/.ssh/config`:
```
Host storagebox
    HostName u123456.your-storagebox.de
    User u123456
    IdentityFile ~/.ssh/storagebox_backup
```

### 2. Configure Environment Variables

Create `.env.backup` or export variables:

```bash
# .env.backup
export DATABASE_URL=ecto://postgres:password@localhost/portfolio_prod
export APP_STORAGE=/app/priv/static/uploads
export STORAGE_BOX=storagebox
export STORAGE_BOX_PATH=/backups/portfolio
export BACKUP_RETENTION_DAYS=7
export HEALTHCHECK_PING_URL=https://hc-ping.com/your-uuid  # Optional
```

Load before running:
```bash
source .env.backup
./scripts/backup.sh production
```

### 3. Set Up Automated Backups

#### Using Cron

```bash
# Copy example crontab
cp config/crontab.example config/crontab

# Edit with your configuration
nano config/crontab

# Install crontab
crontab config/crontab

# Verify
crontab -l
```

Example cron schedule:
```cron
# Daily backup at 3:00 AM
0 3 * * * cd /app && ./scripts/backup.sh production >> /var/log/portfolio_backup.log 2>&1

# Verify backup at 4:00 AM
0 4 * * * cd /app && ./scripts/check_backup.sh production >> /var/log/portfolio_backup_check.log 2>&1
```

#### Using Systemd Timers (Alternative)

Create `/etc/systemd/system/portfolio-backup.service`:
```ini
[Unit]
Description=Portfolio Backup
After=postgresql.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/app
EnvironmentFile=/app/.env.backup
ExecStart=/app/scripts/backup.sh production
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/portfolio-backup.timer`:
```ini
[Unit]
Description=Portfolio Backup Timer

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
systemctl daemon-reload
systemctl enable portfolio-backup.timer
systemctl start portfolio-backup.timer
systemctl status portfolio-backup.timer
```

---

## Monitoring

### Healthchecks.io Setup

1. Create account at https://healthchecks.io (free tier available)
2. Create new check with 26-hour grace period
3. Copy ping URL
4. Add to crontab or environment:

```bash
export HEALTHCHECK_PING_URL=https://hc-ping.com/your-uuid
```

### Manual Verification

Check recent backups:
```bash
# Local backups
ls -lh backups/

# Storage Box backups
ssh storagebox "ls -lh /backups/portfolio/"

# Verify integrity
tar -tzf backups/portfolio_production_20251115_030000.tar.gz
```

Check logs:
```bash
# Backup logs
tail -f /var/log/portfolio_backup.log

# Check logs
tail -f /var/log/portfolio_backup_check.log

# Errors only
grep -i error /var/log/portfolio_backup.log
```

---

## Testing

### Test Backup

Run manual backup:
```bash
# Dry run (check configuration)
DATABASE_URL=$DATABASE_URL \
STORAGE_BOX=storagebox \
./scripts/backup.sh production

# Verify archive created
ls -lh backups/

# Verify uploaded to Storage Box
ssh storagebox "ls -lh /backups/portfolio/"
```

### Test Restoration

**Warning:** Only test on non-production environment!

```bash
# 1. Create test database
createdb portfolio_test

# 2. Restore to test database
DATABASE_URL=ecto://postgres:password@localhost/portfolio_test \
APP_STORAGE=/tmp/test_storage \
./scripts/restore.sh backups/portfolio_production_20251115_030000.tar.gz

# 3. Verify restoration
psql portfolio_test -c "SELECT COUNT(*) FROM users;"
ls -la /tmp/test_storage/
```

### Test Monitoring

```bash
# Should pass if backup exists and is recent
./scripts/check_backup.sh production

# Should fail if no backup
STORAGE_BOX=invalid ./scripts/check_backup.sh production

# Should fail if backup too old
./scripts/check_backup.sh production 1  # Max 1 hour
```

---

## Troubleshooting

### Backup fails with "pg_dump not found"

Install PostgreSQL client:
```bash
# Ubuntu/Debian
apt-get install postgresql-client

# Alpine (Docker)
apk add postgresql-client
```

### Cannot connect to Storage Box

Check SSH configuration:
```bash
# Test connection
ssh -v storagebox

# Check SSH key
ls -la ~/.ssh/storagebox_backup*

# Re-copy key if needed
ssh-copy-id -i ~/.ssh/storagebox_backup.pub u123456@u123456.your-storagebox.de
```

### Backup too large

Check backup size:
```bash
du -sh backups/
du -sh priv/static/uploads/
```

If storage is too large:
- Consider S3/Backblaze for large files
- Compress photos before upload
- Use incremental backups (rsync)

### Restoration fails

Check error messages:
```bash
# Test archive integrity
tar -tzf backup.tar.gz

# Check database permissions
psql $DATABASE_URL -c "SELECT 1;"

# Check storage directory permissions
ls -la priv/static/uploads/
```

---

## Security

### Backup Encryption (Optional)

Encrypt backups before upload:

```bash
# Encrypt
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Decrypt during restoration
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

### Permissions

Set restrictive permissions:
```bash
chmod 700 scripts/*.sh
chmod 600 .env.backup
chown root:root scripts/*.sh
```

### Sensitive Data

Backups contain:
- User emails (RGPD)
- Session tokens (hashed)
- Configuration secrets (.env)

Ensure:
- Storage Box secured with SSH key only
- Backups encrypted if stored externally
- Access restricted (SSH key, firewall)

---

## References

- ADR-045: Backup Automation Strategy
- Storage Box: https://www.hetzner.com/storage/storage-box
- Healthchecks.io: https://healthchecks.io/docs/
