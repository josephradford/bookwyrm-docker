# Bookwyrm Docker Makefile
# Simplifies deployment and maintenance

.PHONY: help setup init start stop restart logs status clean validate env-check clone-repo update

# Bookwyrm repository
BOOKWYRM_REPO := https://github.com/bookwyrm-social/bookwyrm.git
BOOKWYRM_BRANCH := production

# Default target - show help
help:
	@echo "Bookwyrm Docker - Available Commands"
	@echo ""
	@echo "Setup & Deployment:"
	@echo "  make setup      - First time setup (clone repo, build, initialize)"
	@echo "  make init       - Initialize Bookwyrm (migrations, database, themes, static files)"
	@echo "  make env-check  - Verify .env file exists and is configured"
	@echo "  make validate   - Validate docker-compose configuration"
	@echo ""
	@echo "Service Management:"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make status     - Show service status"
	@echo ""
	@echo "Maintenance:"
	@echo "  make update     - Update Bookwyrm (pull latest code, rebuild, restart)"
	@echo "  make logs       - Show logs from all services"
	@echo "  make logs-web   - Show web server logs only"
	@echo "  make logs-nginx - Show nginx logs only"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean      - Remove all containers and volumes (WARNING: destroys data)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. cp .env.example .env"
	@echo "  2. Edit .env with your configuration"
	@echo "  3. make setup"
	@echo "  4. Access at http://localhost:8000"

# Check that .env file exists
env-check:
	@if [ ! -f .env ]; then \
		echo "ERROR: .env file not found!"; \
		echo "Run: cp .env.example .env"; \
		echo "Then edit .env with your configuration"; \
		exit 1; \
	fi
	@echo "✓ .env file exists"

# Validate docker-compose configuration
validate: env-check
	@echo "Validating docker-compose configuration..."
	@docker compose config --quiet
	@echo "✓ Docker Compose configuration is valid"

# Clone Bookwyrm repository if not already present
clone-repo:
	@if [ ! -d "bookwyrm" ]; then \
		echo "Cloning Bookwyrm repository ($(BOOKWYRM_BRANCH) branch)..."; \
		git clone -b $(BOOKWYRM_BRANCH) $(BOOKWYRM_REPO) bookwyrm; \
		echo "✓ Bookwyrm repository cloned"; \
	else \
		echo "✓ Bookwyrm repository already exists"; \
	fi

# Initialize Bookwyrm database and static files
init:
	@echo "Initializing Bookwyrm..."
	@echo "Waiting for containers to be ready..."
	@sleep 10
	@echo ""
	@echo "Step 1/5: Running database migrations..."
	@docker exec bookwyrm python manage.py migrate --no-input
	@echo ""
	@echo "Step 2/5: Initializing database with default data..."
	@if docker exec bookwyrm-db psql -U $${BOOKWYRM_DB_USER:-bookwyrm} -d $${BOOKWYRM_DB_NAME:-bookwyrm} -tAc "SELECT COUNT(*) FROM bookwyrm_connector" 2>/dev/null | grep -q "^0$$"; then \
		echo "Database is empty, running initdb..."; \
		docker exec bookwyrm python manage.py initdb; \
	else \
		echo "Database already initialized, skipping initdb..."; \
	fi
	@echo ""
	@echo "Step 3/5: Compiling theme files..."
	@docker exec bookwyrm python manage.py compile_themes
	@echo ""
	@echo "Step 4/5: Collecting static files..."
	@docker exec bookwyrm python manage.py collectstatic --no-input
	@echo ""
	@echo "Step 5/5: Generating admin code..."
	@docker exec bookwyrm python manage.py admin_code || echo "Note: Admin code generation may fail if admin already exists"
	@echo ""
	@echo "✓ Bookwyrm initialization complete!"
	@echo ""
	@echo "Access Bookwyrm at: http://localhost:$${BOOKWYRM_PORT:-8000}"
	@echo "Use the admin code above to create your first admin account (if shown)"

# First time setup
setup: env-check validate clone-repo
	@echo "Starting Bookwyrm setup..."
	@echo ""
	@echo "Step 1/4: Building Bookwyrm from source (this may take several minutes)..."
	@docker compose build bookwyrm bookwyrm-celery bookwyrm-celery-beat
	@echo ""
	@echo "Step 2/4: Pulling pre-built images (PostgreSQL, Redis, nginx)..."
	@docker compose pull --ignore-pull-failures
	@echo ""
	@echo "Step 3/4: Starting all services..."
	@docker compose up -d
	@echo ""
	@echo "Step 4/4: Initializing Bookwyrm database and static files..."
	@$(MAKE) init
	@echo ""
	@docker compose ps
	@echo ""
	@echo "✓ Setup complete! Bookwyrm is running."
	@echo ""
	@echo "Access your Bookwyrm instance at: http://localhost:$${BOOKWYRM_PORT:-8000}"
	@echo ""
	@echo "Check logs with: make logs"

# Update Bookwyrm to latest version
update: env-check validate
	@echo "Updating Bookwyrm..."
	@echo ""
	@echo "Step 1/5: Pulling latest Bookwyrm source code..."
	@cd bookwyrm && git pull origin $(BOOKWYRM_BRANCH)
	@echo ""
	@echo "Step 2/5: Rebuilding Bookwyrm containers..."
	@docker compose build --no-cache bookwyrm bookwyrm-celery bookwyrm-celery-beat
	@echo ""
	@echo "Step 3/5: Pulling latest images for other services..."
	@docker compose pull --ignore-pull-failures
	@echo ""
	@echo "Step 4/5: Restarting services with new images..."
	@docker compose up -d
	@echo ""
	@echo "Step 5/5: Running database migrations (if any)..."
	@sleep 10
	@docker exec bookwyrm python manage.py migrate --no-input
	@docker exec bookwyrm python manage.py compile_themes
	@docker exec bookwyrm python manage.py collectstatic --no-input
	@echo ""
	@echo "✓ Update complete! Bookwyrm restarted with latest version."
	@echo ""
	@docker compose ps

# Start all services
start: env-check
	@echo "Starting Bookwyrm..."
	@docker compose up -d
	@echo "✓ Bookwyrm started"
	@echo ""
	@echo "Access at: http://localhost:$${BOOKWYRM_PORT:-8000}"

# Stop all services
stop:
	@echo "Stopping Bookwyrm..."
	@docker compose down
	@echo "✓ Bookwyrm stopped"

# Restart all services
restart: env-check
	@echo "Restarting Bookwyrm..."
	@docker compose restart
	@echo "✓ Bookwyrm restarted"

# Show service status
status:
	@docker compose ps

# View logs from all services
logs:
	@docker compose logs -f

# View logs from web service only
logs-web:
	@docker compose logs -f bookwyrm bookwyrm-celery bookwyrm-celery-beat

# View logs from nginx only
logs-nginx:
	@docker compose logs -f nginx

# Clean up (WARNING: destroys data)
clean:
	@echo "WARNING: This will remove all containers and volumes, destroying all data!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@echo "Stopping and removing all containers and volumes..."
	@docker compose down -v
	@echo "✓ Cleanup complete"
	@echo ""
	@echo "Note: The bookwyrm source code directory and data/ directory still exist."
	@echo "To completely reset, also run: rm -rf bookwyrm/ data/"
