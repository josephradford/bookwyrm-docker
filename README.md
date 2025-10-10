# Bookwyrm Docker

**Production-ready Docker Compose deployment for Bookwyrm, the federated social
reading platform.**

This project provides a complete, ready-to-deploy Docker setup for
[Bookwyrm](https://joinbookwyrm.com/) that handles all the complexity of
building from source, configuring nginx, compiling static assets, and
initializing the database.

## Why This Project Exists

Bookwyrm doesn't publish pre-built Docker images, requiring users to build from
the official Git repository. This project solves the deployment complexity by
providing:

✅ Complete multi-container setup (web, database, cache, workers, reverse proxy)
✅ Automated build and initialization process
✅ Production-ready nginx configuration for static file serving
✅ Comprehensive environment variable configuration
✅ Database migration and static asset compilation handled automatically
✅ Simple Makefile commands for deployment and maintenance

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/yourname/bookwyrm-docker.git
cd bookwyrm-docker

# 2. Create and configure environment file
cp .env.example .env
nano .env  # Edit with your configuration

# 3. Run setup (builds images, starts services, initializes database)
make setup

# 4. Access Bookwyrm
open http://localhost:8000
```

The setup process takes 5-10 minutes on first run (building from source).

## Architecture

### Services

This deployment includes 7 Docker containers:

| Service | Purpose | Image/Build |
|---------|---------|-------------|
| `bookwyrm` | Web application (Django/Gunicorn) | Built from source |
| `nginx` | Reverse proxy, serves static files | `nginx:alpine` |
| `bookwyrm-db` | PostgreSQL database | `postgres:16-alpine` |
| `bookwyrm-redis-activity` | Redis for activity streams | `redis:7.2-alpine` |
| `bookwyrm-redis-broker` | Redis for Celery task queue | `redis:7.2-alpine` |
| `bookwyrm-celery` | Background task worker | Built from source |
| `bookwyrm-celery-beat` | Scheduled task scheduler | Built from source |

### Data Persistence

All data is stored in the `data/` directory:

```text
data/
├── pgdata/          # PostgreSQL database
├── redis-activity/  # Redis persistence (activity)
├── redis-broker/    # Redis persistence (Celery)
└── images/          # User-uploaded book covers and images
```

**Important:** Backup the `data/` directory regularly to preserve your Bookwyrm instance.

### Network Architecture

```text
                                  ┌──────────────┐
                                  │    nginx     │
                                  │   (port 8000)│
                                  └──────┬───────┘
                                         │
                        ┌────────────────┼────────────────┐
                        │                │                │
                  ┌─────▼──────┐  ┌─────▼──────┐  ┌─────▼──────┐
                  │  bookwyrm  │  │   celery   │  │celery-beat │
                  │    (web)   │  │  (worker)  │  │(scheduler) │
                  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
                        │                │                │
        ┌───────────────┼────────────────┼────────────────┘
        │               │                │
  ┌─────▼──────┐  ┌────▼─────┐  ┌───────▼────────┐
  │ PostgreSQL │  │  Redis    │  │     Redis      │
  │    (DB)    │  │(activity) │  │   (broker)     │
  └────────────┘  └───────────┘  └────────────────┘
```

### Static File Handling

The project solves Bookwyrm's static file complexity:

1. **SCSS Compilation:** Theme files are compiled from SCSS to CSS
2. **Static Collection:** All static assets gathered via `collectstatic`
3. **Nginx Serving:** Static files served directly by nginx (not Django)
4. **Volume Sharing:** `bookwyrm_static` volume shared between web and nginx

This approach provides **fast static file delivery** and follows Bookwyrm's official production architecture.

## Configuration

### Required Environment Variables

Edit `.env` with at minimum:

```bash
# Domain where Bookwyrm is accessible
BOOKWYRM_DOMAIN=bookwyrm.local

# Secret key (generate with: openssl rand -base64 45)
BOOKWYRM_SECRET_KEY=your_unique_secret_key_here

# Database password
BOOKWYRM_DB_PASSWORD=your_secure_database_password

# Redis passwords
BOOKWYRM_REDIS_ACTIVITY_PASSWORD=your_redis_activity_password
BOOKWYRM_REDIS_BROKER_PASSWORD=your_redis_broker_password
```

### Optional Configuration

```bash
# Port (default: 8000)
BOOKWYRM_PORT=8000

# HTTPS (requires reverse proxy with SSL)
BOOKWYRM_USE_HTTPS=false

# Email (for notifications and password resets)
BOOKWYRM_EMAIL_HOST=smtp.gmail.com
BOOKWYRM_EMAIL_USER=your_email@gmail.com
BOOKWYRM_EMAIL_PASSWORD=your_app_password

# Timezone
TIMEZONE=America/New_York
```

See [`.env.example`](./.env.example) for all available options with detailed documentation.

## Usage

### Setup Commands

```bash
# First time setup
make setup            # Clone repo, build, start, initialize

# Environment validation
make env-check        # Verify .env file exists
make validate         # Validate docker-compose configuration
```

### Service Management

```bash
make start            # Start all services
make stop             # Stop all services
make restart          # Restart all services
make status           # Show service status
```

### Maintenance

```bash
make update           # Update to latest Bookwyrm version
make logs             # View all logs
make logs-web         # View web server logs only
make logs-nginx       # View nginx logs only
```

### Initialization

The `make init` command runs the complete Bookwyrm initialization sequence:

1. **Database migrations** - Create tables and apply schema changes
2. **Database initialization** - Add default connectors and settings
3. **Theme compilation** - Compile SCSS to CSS
4. **Static collection** - Gather all static files
5. **Admin code generation** - Generate code for creating first admin user

This is automatically run during `make setup`, but can be run manually if needed.

## Production Deployment

### HTTPS Setup

For production, set up a reverse proxy (nginx, Caddy, or Traefik) in front of this stack:

```nginx
# Example nginx configuration
server {
    listen 443 ssl http2;
    server_name bookwyrm.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then set in `.env`:
```bash
BOOKWYRM_USE_HTTPS=true
BOOKWYRM_CSRF_TRUSTED_ORIGINS=https://bookwyrm.example.com
```

### Backups

**Database backup:**
```bash
docker exec bookwyrm-db pg_dump -U bookwyrm bookwyrm > backup.sql
```

**Full data backup:**
```bash
tar czf bookwyrm-backup-$(date +%Y%m%d).tar.gz data/
```

**Restore database:**
```bash
cat backup.sql | docker exec -i bookwyrm-db psql -U bookwyrm -d bookwyrm
```

### Monitoring

Check service health:
```bash
make status                          # Container status
docker compose logs --tail=100       # Recent logs
docker stats                         # Resource usage
```

Health check endpoints:

- Nginx: `http://localhost:8000` (should return Bookwyrm homepage)
- Database: Built-in health checks via `pg_isready`
- Redis: Built-in health checks via `redis-cli ping`

## Troubleshooting

### Container Keeps Restarting

**Check logs:**
```bash
make logs-web
```

**Common issues:**

1. **Database not ready** - Wait 30 seconds and check again
2. **Missing environment variables** - Run `make env-check`
3. **Port conflict** - Change `BOOKWYRM_PORT` in `.env`

### Static Files Not Loading (Plain Text Website)

Run the initialization sequence:
```bash
make init
```

This compiles themes and collects static files.

### Database Connection Errors

**Verify database is healthy:**
```bash
docker compose ps bookwyrm-db
```

**Check database logs:**
```bash
docker compose logs bookwyrm-db
```

**Reset database (WARNING: destroys data):**
```bash
docker compose down -v
rm -rf data/pgdata
make setup
```

### Volume Mount Issues

If you see "module not found" errors, check volume mounts:
```bash
docker exec bookwyrm ls -la /app/bookwyrm/static/css/
```

Should show SCSS files. If empty, the volume mount shadowed the source files.

### Complete Reset

To start fresh (destroys all data):
```bash
make clean
rm -rf bookwyrm/ data/
make setup
```

See [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) for more solutions.

## Documentation

- **[Installation Guide](./docs/INSTALLATION.md)** - Detailed setup instructions
- **[Troubleshooting Guide](./docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Environment Variables](./docs/ENVIRONMENT.md)** - Complete environment variable reference
- **[Architecture](./docs/ARCHITECTURE.md)** - Design decisions and technical details

## Project Structure

```text
bookwyrm-docker/
├── docker-compose.yml        # Container orchestration
├── Makefile                  # Deployment commands
├── .env.example              # Environment template
├── config/
│   └── nginx.conf            # Nginx reverse proxy configuration
├── bookwyrm/                 # Bookwyrm source (cloned during setup)
├── data/                     # Persistent data (created during setup)
│   ├── pgdata/               # PostgreSQL database
│   ├── redis-activity/       # Redis persistence
│   ├── redis-broker/         # Redis persistence
│   └── images/               # Uploaded images
└── docs/                     # Documentation
    ├── INSTALLATION.md
    ├── TROUBLESHOOTING.md
    ├── ENVIRONMENT.md
    └── ARCHITECTURE.md
```

## Requirements

- Docker 20.10+
- Docker Compose 2.0+
- 2GB RAM minimum (4GB recommended)
- 10GB disk space

## Contributing

Contributions are welcome! This project aims to make Bookwyrm deployment as simple as possible.

**Areas for contribution:**

- Improved documentation
- Additional deployment scenarios (Kubernetes, cloud platforms)
- Monitoring and observability integrations
- Backup/restore scripts
- Security hardening

## License

This project is MIT licensed. Bookwyrm itself is licensed under the Anti-Capitalist Software License.

## Acknowledgments

- [Bookwyrm](https://github.com/bookwyrm-social/bookwyrm) - The amazing federated reading platform
- [BookWyrm Documentation](https://docs.joinbookwyrm.com/) - Official deployment guides

## Related Projects

- [bookwyrm-social/bookwyrm](https://github.com/bookwyrm-social/bookwyrm) - Official Bookwyrm repository
- Looking for other self-hosted services? Check out [awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted)

## Support

- **Issues:** [GitHub Issues](https://github.com/yourname/bookwyrm-docker/issues)
- **Bookwyrm Help:** [Bookwyrm Community](https://joinbookwyrm.com/)
- **Matrix Chat:** Join the Bookwyrm community chat

---

**Star this repo if it helped you deploy Bookwyrm!** ⭐
