# Pre-production Environment

Docker-based pre-production environment for testing production-like deployment before actual release.

## Quick Start

```bash
# Initial setup
./scripts/preprod/setup.sh

# Access application
open http://localhost:4001

# View logs
docker-compose -f docker-compose.preprod.yml logs -f

# Deploy new version
./scripts/preprod/deploy.sh

# Stop environment
docker-compose -f docker-compose.preprod.yml down
```

## Overview

The pre-production environment mirrors the production architecture:
- **PostgreSQL 16**: Production database version
- **Phoenix Application**: Built with production mix environment
- **Multi-stage Docker Build**: Optimized for size and security
- **Health Checks**: Automated service monitoring
- **Persistent Volumes**: Data survives container restarts
- **Resource Limits**: CPU/Memory constraints like production

## Requirements

### System Requirements
- Docker 20.10+ 
- Docker Compose 2.0+
- 2GB free disk space
- 2GB free RAM

### Installation

**macOS:**
```bash
brew install docker docker-compose
```

**Ubuntu:**
```bash
sudo apt-get install docker.io docker-compose
sudo usermod -aG docker $USER
# Logout and login again
```

**Windows:**
Download Docker Desktop from https://docker.com

## Setup

### Initial Setup

Run the setup script to initialize everything:

```bash
./scripts/preprod/setup.sh
```

This script will:
1. Check Docker installation
2. Generate secrets (.env.preprod)
3. Build Docker images
4. Start services
5. Run database migrations
6. Verify health

**Output:**
```
[INFO] Checking Docker installation...
[INFO] Docker version 24.0.7 found
[INFO] Generating secrets...
[INFO] Building Docker images...
[INFO] Starting services...
[INFO] Waiting for services to be healthy...
[INFO] Running database migrations...
[INFO] Setup Complete
```

### Manual Setup

If you prefer manual steps:

```bash
# 1. Generate secrets
mix phx.gen.secret  # Copy to .env.preprod as SECRET_KEY_BASE

# 2. Build images
docker-compose -f docker-compose.preprod.yml build

# 3. Start services
docker-compose -f docker-compose.preprod.yml up -d

# 4. Run migrations
docker-compose -f docker-compose.preprod.yml exec app /app/bin/portfolio eval "Portfolio.Release.migrate()"

# 5. Verify
curl http://localhost:4001/health
```

## Usage

### Starting/Stopping

```bash
# Start all services
docker-compose -f docker-compose.preprod.yml up -d

# Stop all services
docker-compose -f docker-compose.preprod.yml down

# Stop and remove volumes (⚠️ deletes data)
docker-compose -f docker-compose.preprod.yml down -v

# Restart specific service
docker-compose -f docker-compose.preprod.yml restart app
```

### Viewing Logs

```bash
# All services
docker-compose -f docker-compose.preprod.yml logs -f

# Specific service
docker-compose -f docker-compose.preprod.yml logs -f app
docker-compose -f docker-compose.preprod.yml logs -f postgres

# Last 100 lines
docker-compose -f docker-compose.preprod.yml logs --tail=100 app
```

### Accessing Services

| Service | URL/Connection | Credentials |
|---------|----------------|-------------|
| Application | http://localhost:4001 | Via magic link |
| PostgreSQL | localhost:5433 | portfolio / portfolio_preprod_password |
| Health Check | http://localhost:4001/health | - |

### Shell Access

```bash
# Application container shell
docker-compose -f docker-compose.preprod.yml exec app sh

# PostgreSQL shell
docker-compose -f docker-compose.preprod.yml exec postgres psql -U portfolio -d portfolio_preprod

# Run Elixir console
docker-compose -f docker-compose.preprod.yml exec app /app/bin/portfolio remote
```

## Deployment

### Deploy New Version

```bash
./scripts/preprod/deploy.sh
```

This performs:
1. Pre-deployment backup
2. Build new Docker image
3. Run database migrations
4. Deploy new version (zero-downtime)
5. Health check verification
6. Cleanup old images

**Skip build** (use existing image):
```bash
./scripts/preprod/deploy.sh --no-build
```

### Rollback

```bash
# 1. Find previous image
docker images | grep portfolio

# 2. Tag as current
docker tag portfolio:previous portfolio:preprod

# 3. Deploy
./scripts/preprod/deploy.sh --no-build

# 4. Restore database if needed
./scripts/backup/restore-postgres.sh backups/preprod/postgres_preprod_*.sql.gz
```

## Testing

### Smoke Tests

```bash
# Health check
curl http://localhost:4001/health
# Expected: OK

# Homepage
curl -I http://localhost:4001/
# Expected: 200 OK

# Static assets
curl -I http://localhost:4001/assets/app.css
# Expected: 200 OK
```

### Load Testing

```bash
# Install hey (HTTP load generator)
brew install hey  # macOS
# or download from https://github.com/rakyll/hey

# Run load test (100 requests, 10 concurrent)
hey -n 100 -c 10 http://localhost:4001/

# Stress test
hey -n 1000 -c 50 -t 30 http://localhost:4001/
```

### Database Testing

```bash
# Connect to database
docker-compose -f docker-compose.preprod.yml exec postgres psql -U portfolio -d portfolio_preprod

# Check tables
\dt

# Check data
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM photos;

# Query performance
EXPLAIN ANALYZE SELECT * FROM photos WHERE album_id = '...';
```

## Configuration

### Environment Variables

Edit `.env.preprod` or `docker-compose.preprod.yml`:

```env
# Database
DATABASE_URL=ecto://portfolio:password@postgres:5432/portfolio_preprod

# Application
PHX_HOST=preprod.example.com  # Change for external access
SECRET_KEY_BASE=...           # Generate with mix phx.gen.secret

# Email (configure SMTP for actual preprod)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

### Resource Limits

Edit `docker-compose.preprod.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'      # Maximum 2 CPUs
      memory: 1G       # Maximum 1GB RAM
    reservations:
      cpus: '1.0'      # Reserved 1 CPU
      memory: 512M     # Reserved 512MB
```

### Volumes

Persistent data locations:

```
volumes/
  ├── postgres_data/     # Database files
  ├── uploads/           # Uploaded photos
  └── backups/           # Backup files
```

## Monitoring

### Service Status

```bash
# Check all services
docker-compose -f docker-compose.preprod.yml ps

# Check health
docker-compose -f docker-compose.preprod.yml ps | grep healthy
```

### Resource Usage

```bash
# CPU/Memory usage
docker stats

# Disk usage
docker system df

# Volume sizes
docker system df -v
```

### Application Metrics

```bash
# Phoenix metrics endpoint (if configured)
curl http://localhost:4001/metrics

# Oban dashboard (if configured)
open http://localhost:4001/admin/oban
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker-compose -f docker-compose.preprod.yml logs

# Check Docker daemon
docker info

# Restart Docker
sudo systemctl restart docker  # Linux
# or restart Docker Desktop (macOS/Windows)
```

### Database Connection Failed

```bash
# Check PostgreSQL is running
docker-compose -f docker-compose.preprod.yml ps postgres

# Check PostgreSQL logs
docker-compose -f docker-compose.preprod.yml logs postgres

# Test connection
docker-compose -f docker-compose.preprod.yml exec postgres pg_isready -U portfolio

# Recreate database
docker-compose -f docker-compose.preprod.yml down -v
docker-compose -f docker-compose.preprod.yml up -d
```

### Application Errors

```bash
# View application logs
docker-compose -f docker-compose.preprod.yml logs -f app

# Check application status
curl http://localhost:4001/health

# Restart application
docker-compose -f docker-compose.preprod.yml restart app

# Access IEx console for debugging
docker-compose -f docker-compose.preprod.yml exec app /app/bin/portfolio remote
```

### Out of Disk Space

```bash
# Remove unused images
docker image prune -a

# Remove stopped containers
docker container prune

# Remove unused volumes (⚠️ data loss)
docker volume prune

# Complete cleanup (⚠️ removes everything)
docker system prune -a --volumes
```

### Port Already in Use

```bash
# Find process using port 4001
lsof -i :4001

# Kill process
kill -9 <PID>

# Or change port in docker-compose.preprod.yml
ports:
  - "4002:4000"  # Use 4002 instead
```

## Maintenance

### Database Backup

```bash
# Manual backup
DATABASE_URL="ecto://portfolio:portfolio_preprod_password@localhost:5433/portfolio_preprod" \
  BACKUP_DIR="./backups/preprod" \
  ./scripts/backup/backup-postgres.sh preprod

# Restore backup
./scripts/backup/restore-postgres.sh backups/preprod/postgres_preprod_*.sql.gz
```

### Update Dependencies

```bash
# Rebuild with latest dependencies
docker-compose -f docker-compose.preprod.yml build --no-cache

# Deploy new version
./scripts/preprod/deploy.sh
```

### Clean Start

```bash
# Stop and remove everything
docker-compose -f docker-compose.preprod.yml down -v

# Remove images
docker rmi portfolio:preprod

# Start fresh
./scripts/preprod/setup.sh
```

## Best Practices

### Pre-deployment Checklist

- [ ] Run tests locally: `mix test`
- [ ] Check code quality: `mix precommit`
- [ ] Review changes: `git diff main`
- [ ] Update CHANGELOG.md
- [ ] Test in preprod first
- [ ] Monitor logs after deployment
- [ ] Verify critical features
- [ ] Check performance metrics

### Security

1. **Never commit secrets** to version control
   ```bash
   # Add to .gitignore
   .env.preprod
   ```

2. **Rotate secrets regularly**
   ```bash
   mix phx.gen.secret  # Generate new SECRET_KEY_BASE
   ```

3. **Use strong passwords**
   ```bash
   openssl rand -base64 32  # Generate secure password
   ```

4. **Restrict access** (use firewall rules)
   ```bash
   # Allow only specific IPs
   iptables -A INPUT -p tcp --dport 4001 -s YOUR_IP -j ACCEPT
   ```

### Performance

1. **Monitor resource usage**
2. **Set appropriate limits** in docker-compose.yml
3. **Use production-like data volume**
4. **Test with realistic load**

## Differences from Production

| Feature | Pre-prod | Production |
|---------|----------|------------|
| Database | PostgreSQL 16 (Docker) | PostgreSQL 16 (managed) |
| Secrets | .env.preprod | Environment variables |
| SSL/TLS | HTTP only | HTTPS required |
| Domain | localhost:4001 | portfolio.example.com |
| Backups | Manual/scripted | Automated with monitoring |
| Monitoring | Docker stats | Full APM suite |
| Scaling | Single container | Multiple instances |

## Support

### Getting Help

1. Check logs first
2. Review this documentation
3. Search Docker documentation
4. Check application logs

### Useful Links

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)

## Next Steps

After validating in pre-production:
1. Tag release: `git tag v1.0.0`
2. Push to repository: `git push --tags`
3. Deploy to production with Kamal
4. Monitor production metrics
5. Keep preprod environment for future testing
