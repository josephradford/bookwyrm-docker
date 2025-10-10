# Bookwyrm Docker Troubleshooting Guide

This guide covers common issues encountered during Bookwyrm deployment and their solutions.

## Table of Contents

1. [Container Issues](#container-issues)
1. [Static File Problems](#static-file-problems)
1. [Database Issues](#database-issues)
1. [Network and Port Conflicts](#network-and-port-conflicts)
1. [Volume Mount Problems](#volume-mount-problems)
1. [Performance Issues](#performance-issues)

---

## Container Issues

### Container Keeps Restarting

**Symptom:** `docker compose ps` shows container repeatedly restarting

**Diagnosis:**

```bash
make logs-web
docker compose logs bookwyrm --tail=50
```

**Common Causes:**

#### 1. Missing Gunicorn Command

**Error:** Container starts Python interpreter and exits immediately

**Solution:** Verify `docker-compose.yml` has:

```yaml
bookwyrm:
  command: gunicorn bookwyrm.wsgi:application --bind 0.0.0.0:8000
```

#### 2. Database Not Ready

**Error:** `connection refused` or `could not connect to server`

**Solution:** Wait 30 seconds for database to initialize, then check:

```bash
docker compose ps bookwyrm-db  # Should show "healthy"
```

#### 3. Missing Environment Variables

**Error:** `Environment variable "EMAIL_HOST" not set`

**Solution:** Ensure `.env` has all required variables:

```bash
make env-check
make validate
```

Add missing variables to `.env` (see `.env.example`)

### Container Exits with Code 0

**Symptom:** Container starts then immediately exits cleanly

**Cause:** Missing startup command or command exits successfully

**Solution:**

1. Check `docker-compose.yml` has proper `command:` directive
1. For `bookwyrm` service: `command: gunicorn bookwyrm.wsgi:application --bind 0.0.0.0:8000`
1. For workers: Verify Celery commands are correct

---

## Static File Problems

### Website Shows Plain Text (No CSS Styling)

**Symptom:** Bookwyrm loads but has no styling, looks like plain HTML

**Cause:** Static files (CSS, JavaScript) not compiled or not being served

**Solution:**

#### Step 1: Verify Static Files Exist

```bash
docker exec bookwyrm ls -la /app/bookwyrm/static/css/themes/
```

Should show `bookwyrm-light.css` and `bookwyrm-dark.css`

If missing:

```bash
docker exec bookwyrm python manage.py compile_themes
```

#### Step 2: Collect Static Files

```bash
docker exec bookwyrm python manage.py collectstatic --no-input
```

Verify files collected:

```bash
docker exec bookwyrm ls -la /app/static/css/themes/
```

#### Step 3: Check Nginx Configuration

```bash
docker compose logs nginx
```

Look for 404 errors on `/static/` paths

Verify nginx is running:

```bash
docker compose ps nginx  # Should show "Up"
```

#### Step 4: Full Re-initialization

If above steps don't work:

```bash
make init
docker compose restart nginx bookwyrm
```

### SCSS Files Not Found

**Error:** `Unable to locate file css/themes/bookwyrm-light.scss`

**Cause:** Volume mount shadowing static directory

**Diagnosis:**

```bash
docker exec bookwyrm find /app -name "*.scss" | head -10
```

Should show SCSS files. If empty, volume mount is shadowing.

**Solution:**

Check `docker-compose.yml` volumes for `bookwyrm` service. Should NOT have:

```yaml
# BAD - shadows static files:
volumes:
  - ./data/static:/app/bookwyrm/static
```

Should have:

```yaml
# GOOD:
volumes:
  - ./bookwyrm:/app
  - ./data/images:/app/bookwyrm/static/images
  - bookwyrm_static:/app/static
```

Fix and recreate:

```bash
docker compose up -d --force-recreate bookwyrm
make init
```

---

## Database Issues

### Database Connection Failed

**Error:** `FATAL: password authentication failed for user "bookwyrm"`

**Cause:** Database password mismatch

**Solution:**

#### Option 1: Use Correct Password

Check `.env`:

```bash
grep BOOKWYRM_DB_PASSWORD .env
```

The password in `.env` must match what's in the database (set during first initialization).

#### Option 2: Reset Database

##### WARNING: Destroys all data

```bash
docker compose down
rm -rf data/pgdata
docker compose up -d
# Wait for database to initialize (30 seconds)
make init
```

### Database Tables Don't Exist

**Error:** `relation "bookwyrm_sitesettings" does not exist`

**Cause:** Migrations not run

**Solution:**

```bash
docker exec bookwyrm python manage.py migrate --no-input
docker exec bookwyrm python manage.py initdb
docker exec bookwyrm python manage.py compile_themes
docker exec bookwyrm python manage.py collectstatic --no-input
```

Or simply:

```bash
make init
```

### Duplicate Key Violation on initdb

**Error:** `duplicate key value violates unique constraint "bookwyrm_connector_identifier_key"`

**Cause:** Database already initialized, `initdb` not idempotent

**Solution:** Skip `initdb`, run other steps:

```bash
docker exec bookwyrm python manage.py migrate --no-input
docker exec bookwyrm python manage.py compile_themes
docker exec bookwyrm python manage.py collectstatic --no-input
```

The `make init` command handles this automatically.

---

## Network and Port Conflicts

### Port Already in Use

**Error:** `Bind for 0.0.0.0:8000 failed: port is already allocated`

**Diagnosis:**

```bash
# Find what's using port 8000
lsof -i :8000
# Or on Linux:
sudo netstat -tlnp | grep :8000
```

**Solution:**

#### Option 1: Change Bookwyrm Port

Edit `.env`:

```bash
BOOKWYRM_PORT=8080  # Or any available port
```

Restart:

```bash
docker compose down
docker compose up -d
```

#### Option 2: Stop Conflicting Service

```bash
# If another Docker container:
docker ps  # Find container ID
docker stop <container-id>

# If system service:
sudo systemctl stop <service-name>
```

### Cannot Access from Network

**Symptom:** Bookwyrm works on `localhost` but not from other devices

**Solution:**

1. Check firewall allows port:

```bash
# UFW (Ubuntu):
sudo ufw allow 8000

# Firewalld (CentOS/RHEL):
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload
```

1. Verify docker binding:

```bash
docker compose ps nginx
```

Should show: `0.0.0.0:8000->80/tcp` (not `127.0.0.1:8000`)

1. Check `BOOKWYRM_CSRF_TRUSTED_ORIGINS` in `.env`:

```bash
BOOKWYRM_CSRF_TRUSTED_ORIGINS=http://localhost:8000,http://192.168.1.100:8000
```

---

## Volume Mount Problems

### Source Code Not Visible in Container

**Error:** `ModuleNotFoundError: No module named 'celerywyrm'`

**Cause:** Source code not mounted into container

**Diagnosis:**

```bash
docker exec bookwyrm ls -la /app/bookwyrm/
```

Should show Python files. If empty, volume mount failed.

**Solution:**

Verify `docker-compose.yml`:

```yaml
bookwyrm:
  volumes:
    - ./bookwyrm:/app  # Must exist
```

Check Bookwyrm repo cloned:

```bash
ls -la bookwyrm/
```

If missing:

```bash
make clone-repo
docker compose up -d --force-recreate bookwyrm
```

### Volume Permissions Issues

**Error:** `Permission denied` when writing files

**Cause:** Container user doesn't have write permissions

**Solution:**

Fix permissions on host:

```bash
chmod -R 755 data/
chown -R $(id -u):$(id -g) data/
```

Or run container as specific user (add to service in `docker-compose.yml`):

```yaml
user: "1000:1000"  # Your user ID
```

---

## Performance Issues

### Slow Initial Load

**Cause:** First request compiles templates and loads caches

**Normal behavior:** First load takes 5-10 seconds, subsequent loads are fast

**To improve:**

1. Increase container resources (in Docker Desktop settings)
1. Use SSD for data volumes
1. Enable Django caching (requires Redis configuration)

### High Memory Usage

**Symptom:** Containers using excessive RAM

**Diagnosis:**

```bash
docker stats
```

**Solutions:**

1. **Limit container memory** (add to service in `docker-compose.yml`):

```yaml
deploy:
  resources:
    limits:
      memory: 1G
```

1. **Reduce Gunicorn workers** (modify command):

```yaml
command: gunicorn bookwyrm.wsgi:application --bind 0.0.0.0:8000 --workers 2
```

1. **Optimize PostgreSQL** (add to bookwyrm-db environment):

```yaml
environment:
  - shared_buffers=256MB
  - effective_cache_size=1GB
```

### Slow Database Queries

**Cause:** Database not optimized

**Solution:**

Run vacuum and analyze:

```bash
docker exec bookwyrm-db vacuumdb -U bookwyrm -d bookwyrm -z
```

Check database size:

```bash
docker exec bookwyrm-db psql -U bookwyrm -d bookwyrm -c "
  SELECT pg_size_pretty(pg_database_size('bookwyrm'));"
```

---

## Complete Reset Procedure

If all else fails, complete reset (destroys all data):

```bash
# 1. Stop and remove everything
docker compose down -v

# 2. Remove persistent data
rm -rf data/
rm -rf bookwyrm/

# 3. Verify .env configuration
make env-check

# 4. Fresh setup
make setup

# 5. Verify it works
docker compose ps
curl http://localhost:8000
```

---

## Getting Help

If this guide doesn't solve your issue:

1. **Check logs:**

   ```bash
   make logs > bookwyrm-logs.txt
   ```

1. **Gather system info:**

   ```bash
   docker version
   docker compose version
   docker compose config
   ```

1. **Create GitHub Issue:**
   - Include logs
   - Include docker-compose config output
   - Describe what you tried
   - Note your environment (OS, Docker version)

1. **Bookwyrm Community:**
   - Official docs: [https://docs.joinbookwyrm.com/](https://docs.joinbookwyrm.com/)
   - Matrix chat: [https://matrix.to/#/#bookwyrm:matrix.org](https://matrix.to/#/#bookwyrm:matrix.org)
   - GitHub: [https://github.com/bookwyrm-social/bookwyrm/issues](https://github.com/bookwyrm-social/bookwyrm/issues)

---

## Preventive Measures

**Avoid future issues:**

1. **Regular backups:**

   ```bash
   tar czf backup-$(date +%Y%m%d).tar.gz data/
   ```

1. **Monitor logs:**

   ```bash
   docker compose logs -f --tail=100
   ```

1. **Keep updated:**

   ```bash
   make update  # Updates Bookwyrm monthly
   ```

1. **Test before production:**
   - Deploy in staging first
   - Test all functionality
   - Verify backups restore correctly

1. **Document customizations:**
   - Note any changes to docker-compose.yml
   - Keep list of installed plugins/themes
   - Track environment variable changes
