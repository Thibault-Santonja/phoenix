# Backup and Restore Scripts

Automated backup solution for Portfolio application with PostgreSQL database and photo uploads.

## Quick Start

```bash
# Backup everything
./scripts/backup/backup-postgres.sh production
./scripts/backup/backup-photos.sh production

# Restore from backup
./scripts/backup/restore-postgres.sh backups/postgres/postgres_production_20250113_143022.sql.gz
./scripts/backup/restore-photos.sh backups/photos/photos_production_20250113_143022.tar.gz
```

## Scripts Overview

### Backup Scripts

#### `backup-postgres.sh`
Backs up PostgreSQL database to compressed SQL dump.

**Features:**
- Compressed gzip output
- Automatic retention management (30 days default)
- Optional S3 upload
- Integrity verification
- Transaction-safe dumps

**Usage:**
```bash
./backup-postgres.sh [environment]

# Examples
./backup-postgres.sh production
./backup-postgres.sh staging
DATABASE_URL="postgresql://..." ./backup-postgres.sh production
```

#### `backup-photos.sh`
Creates compressed tar archive of uploaded photos.

**Features:**
- Compressed tar.gz output
- Handles empty photo directories
- Automatic retention management
- Optional S3 upload
- Integrity verification

**Usage:**
```bash
./backup-photos.sh [environment]

# Examples
./backup-photos.sh production
BACKUP_S3_BUCKET="my-bucket" ./backup-photos.sh production
```

### Restore Scripts

#### `restore-postgres.sh`
Restores database from backup file.

**⚠️ DANGER:** This drops the existing database!

**Usage:**
```bash
./restore-postgres.sh <backup_file>

# Example
./restore-postgres.sh backups/postgres/postgres_production_20250113_143022.sql.gz
```

**Safety features:**
- Confirmation prompt
- Backup integrity check
- Detailed error messages

#### `restore-photos.sh`
Restores photos from backup archive.

**⚠️ DANGER:** This replaces existing photos (unless --merge)!

**Usage:**
```bash
./restore-photos.sh <backup_file> [--merge]

# Replace all photos
./restore-photos.sh backups/photos/photos_production_20250113_143022.tar.gz

# Merge with existing photos
./restore-photos.sh backups/photos/photos_production_20250113_143022.tar.gz --merge
```

**Safety features:**
- Confirmation prompt
- Automatic safety backup before restore
- Merge mode to preserve existing photos
- Backup integrity check

## Configuration

### Environment Variables

#### Required

```bash
DATABASE_URL="postgresql://user:password@host:5432/database"
```

#### Optional

```bash
# Backup locations
PHOTOS_DIR="priv/static/uploads/photos"
BACKUP_DIR="./backups"

# Retention
BACKUP_RETENTION_DAYS=30

# S3 remote backups
BACKUP_S3_BUCKET="my-backups-bucket"
AWS_ACCESS_KEY_ID="..."
AWS_SECRET_ACCESS_KEY="..."
AWS_DEFAULT_REGION="eu-west-1"
```

### Automated Backups (Cron)

See `crontab.example` for cron configuration.

**Recommended schedule:**
- PostgreSQL: Daily at 2:00 AM
- Photos: Daily at 3:00 AM  
- S3 upload: Weekly on Sunday

**Setup:**
```bash
# Edit crontab
crontab -e

# Add backup jobs (see crontab.example)
0 2 * * * cd /path/to/portfolio && DATABASE_URL="..." ./scripts/backup/backup-postgres.sh production

# Verify cron jobs
crontab -l
```

## Backup Strategy

### Local Backups

**Location:** `./backups/`
```
backups/
├── postgres/
│   ├── postgres_production_20250113_020000.sql.gz
│   ├── postgres_production_20250114_020000.sql.gz
│   └── ...
└── photos/
    ├── photos_production_20250113_030000.tar.gz
    ├── photos_production_20250114_030000.tar.gz
    └── ...
```

**Retention:** 30 days (configurable)

### Remote Backups (S3)

**Optional but recommended** for disaster recovery.

**Setup:**
```bash
# Install AWS CLI
brew install awscli  # macOS
apt-get install awscli  # Ubuntu

# Configure credentials
aws configure

# Enable S3 backups
export BACKUP_S3_BUCKET="my-backups-bucket"
./scripts/backup/backup-postgres.sh production
```

**S3 Structure:**
```
s3://my-backups-bucket/
├── postgres/
│   └── postgres_production_20250113_020000.sql.gz
└── photos/
    └── photos_production_20250113_030000.tar.gz
```

**Cost optimization:**
- Use S3 Lifecycle Policies
- Transition to Glacier after 90 days
- Delete after 1 year

## Monitoring

### Check Backup Status

```bash
# List recent backups
ls -lht backups/postgres/ | head -5
ls -lht backups/photos/ | head -5

# Check backup sizes
du -sh backups/postgres/
du -sh backups/photos/

# Verify backup integrity
gunzip -t backups/postgres/postgres_production_20250113_020000.sql.gz
tar -tzf backups/photos/photos_production_20250113_030000.tar.gz > /dev/null
```

### Log Monitoring

```bash
# View backup logs
tail -f /var/log/portfolio/backup-postgres.log
tail -f /var/log/portfolio/backup-photos.log

# Check for errors
grep ERROR /var/log/portfolio/backup-*.log
```

### Automated Monitoring

Set up alerts for:
- Backup failures (non-zero exit code)
- Missing backups (no new files in 24h)
- Disk space issues
- S3 upload failures

**Example with Monit:**
```
check file postgres_backup with path /path/to/backups/postgres/
  if timestamp > 25 hours then alert
```

## Testing

### Test Backup Process

```bash
# Run backup in test mode
DATABASE_URL="postgresql://test" BACKUP_DIR="./test_backups" ./scripts/backup/backup-postgres.sh production

# Verify backup was created
ls -lh test_backups/postgres/

# Clean up
rm -rf test_backups/
```

### Test Restore Process

**⚠️ ALWAYS test on non-production environment!**

```bash
# 1. Create test database
createdb portfolio_restore_test

# 2. Restore backup
DATABASE_URL="postgresql://localhost/portfolio_restore_test" \
  ./scripts/backup/restore-postgres.sh backups/postgres/latest.sql.gz

# 3. Verify data
psql portfolio_restore_test -c "SELECT COUNT(*) FROM users;"

# 4. Clean up
dropdb portfolio_restore_test
```

## Disaster Recovery

### Complete System Restore

```bash
# 1. Set up new server
ssh new-server

# 2. Install dependencies
apt-get update
apt-get install postgresql-client gzip tar

# 3. Download backups from S3
aws s3 cp s3://my-backups-bucket/postgres/latest.sql.gz ./
aws s3 cp s3://my-backups-bucket/photos/latest.tar.gz ./

# 4. Restore database
DATABASE_URL="..." ./scripts/backup/restore-postgres.sh latest.sql.gz

# 5. Restore photos
./scripts/backup/restore-photos.sh latest.tar.gz

# 6. Verify application
curl https://new-server.com/health
```

### Recovery Time Objective (RTO)

- **Database restore:** ~5-10 minutes
- **Photos restore:** ~10-30 minutes (depending on size)
- **Total RTO:** ~15-40 minutes

### Recovery Point Objective (RPO)

- **Daily backups:** Max 24 hours data loss
- **Hourly backups:** Max 1 hour data loss (adjust cron)

## Troubleshooting

### Backup fails with "permission denied"

```bash
chmod +x scripts/backup/*.sh
```

### Database backup fails with "password authentication failed"

```bash
# Verify DATABASE_URL
echo $DATABASE_URL

# Test connection
psql "$DATABASE_URL" -c "SELECT 1;"
```

### Photos backup is too large

```bash
# Check photo directory size
du -sh priv/static/uploads/photos/

# Consider:
# - Image optimization (reduce quality, resize)
# - Incremental backups
# - Exclude old/unused photos
```

### S3 upload fails

```bash
# Verify AWS credentials
aws s3 ls s3://my-backups-bucket/

# Check AWS CLI installation
which aws
aws --version

# Test S3 access
aws s3 cp test.txt s3://my-backups-bucket/test.txt
```

## Security Best Practices

1. **Encrypt backups at rest**
   ```bash
   # Use encrypted S3 buckets
   aws s3api put-bucket-encryption --bucket my-backups-bucket ...
   ```

2. **Restrict backup access**
   ```bash
   chmod 700 scripts/backup/
   chmod 600 backups/
   ```

3. **Don't commit credentials**
   ```bash
   # Add to .gitignore
   echo "backups/" >> .gitignore
   echo ".env" >> .gitignore
   ```

4. **Use IAM roles** (for EC2/ECS)
   - No hardcoded AWS credentials
   - Automatic credential rotation

5. **Audit backup access**
   ```bash
   # Enable S3 access logging
   aws s3api put-bucket-logging ...
   ```

## Maintenance

### Regular Tasks

- **Weekly:** Verify backup integrity
- **Monthly:** Test restore procedures
- **Quarterly:** Review retention policies
- **Yearly:** Disaster recovery drill

### Cleanup Old Backups

```bash
# Manual cleanup (older than 30 days)
find backups/postgres/ -name "*.sql.gz" -mtime +30 -delete
find backups/photos/ -name "*.tar.gz" -mtime +30 -delete

# Automatic cleanup is built into backup scripts
```

## Support

For issues or questions:
- Check logs: `/var/log/portfolio/backup-*.log`
- Review script output
- Verify environment variables
- Test with verbose mode: `bash -x ./scripts/backup/backup-postgres.sh`
