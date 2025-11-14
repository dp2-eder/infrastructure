#!/bin/bash
# This script is only for Ubuntu systems
set -e  # Exit on error

# Configuration
CHECKPOINT_FILE="/var/lib/dp2/install_qa.checkpoint"
LOG_FILE="/var/log/dp2_install_qa.log"

# Ensure checkpoint directory exists
sudo mkdir -p "$(dirname "$CHECKPOINT_FILE")"
sudo mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"
}

# Check if a step is already completed
is_step_done() {
    [ -f "$CHECKPOINT_FILE" ] && grep -q "^$1$" "$CHECKPOINT_FILE"
}

# Mark a step as completed
mark_step_done() {
    log "✓ Completed: $1"
    echo "$1" | sudo tee -a "$CHECKPOINT_FILE" >/dev/null
}

# Execute a step only if not already done
run_step() {
    local step_name="$1"
    shift
    
    if is_step_done "$step_name"; then
        log "⊳ Skipping (already done): $step_name"
        return 0
    fi
    
    log "▶ Starting: $step_name"
    if "$@"; then
        mark_step_done "$step_name"
        return 0
    else
        log "✗ Failed: $step_name"
        return 1
    fi
}

log "========================================"
log "Starting DP2 QA Environment Installation"
log "========================================"

# ============================================
# STEP 1: System Update and Base Packages
# ============================================
step_system_update() {
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y git curl wget build-essential nginx
}

run_step "system_update" step_system_update

# ============================================
# STEP 2: MySQL Installation and Configuration
# ============================================
step_mysql_setup() {
    local DB_NAME="dp2_qa_db"
    local DB_USER="dp2_qa_user"
    local DB_PASSWORD="dp2_qa_password"
    
    sudo apt install -y mysql-server
    sudo systemctl start mysql
    sudo systemctl enable mysql
    
    # Wait for MySQL to be ready
    for i in {1..30}; do
        if sudo mysqladmin ping -h localhost --silent; then
            break
        fi
        sleep 1
    done
    
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" || return 1
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';" || return 1
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';" || return 1
    sudo mysql -e "FLUSH PRIVILEGES;" || return 1
    
    return 0
}

run_step "mysql_setup" step_mysql_setup

# ============================================
# STEP 3: RabbitMQ Installation and Configuration
# ============================================
step_rabbitmq_setup() {
    local RABBITMQ_VHOST="dp2_qa_vhost"
    local RABBITMQ_USER="dp2_qa_user"
    local RABBITMQ_PASSWORD="dp2_qa_password"
    
    sudo apt install -y rabbitmq-server
    sudo systemctl enable rabbitmq-server
    sudo systemctl start rabbitmq-server
    
    # Wait for RabbitMQ to be ready
    for i in {1..30}; do
        if sudo rabbitmqctl status >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    sudo rabbitmq-plugins enable rabbitmq_management
    
    # Setup vhost and user
    if sudo rabbitmqctl list_vhosts | grep -q "^${RABBITMQ_VHOST}$"; then
        sudo rabbitmqctl clear_permissions -p "${RABBITMQ_VHOST}" "${RABBITMQ_USER}" >/dev/null 2>&1 || true
    else
        sudo rabbitmqctl add_vhost "${RABBITMQ_VHOST}"
    fi
    
    if sudo rabbitmqctl list_users | grep -q "^${RABBITMQ_USER}\b"; then
        sudo rabbitmqctl change_password "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
    else
        sudo rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
    fi
    
    sudo rabbitmqctl set_permissions -p "${RABBITMQ_VHOST}" "${RABBITMQ_USER}" ".*" ".*" ".*"
    
    return 0
}

run_step "rabbitmq_setup" step_rabbitmq_setup

# ============================================
# STEP 4: Docker Installation
# ============================================
step_docker_install() {
    # Add Docker's official GPG key
    sudo apt update -y
    sudo apt install ca-certificates curl -y
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    
    sudo apt update -y
    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    
    # Post-installation steps
    sudo usermod -aG docker $USER
    
    # Verify Docker installation
    sudo docker --version || return 1
    
    return 0
}

run_step "docker_install" step_docker_install

# ============================================
# STEP 5: Setup Working Directories
# ============================================
step_setup_directories() {
    sudo mkdir -p /var/www/
    sudo chown -R $USER:$USER /var/www/
    sudo chmod -R 755 /var/www/
    
    sudo mkdir -p /mnt/images
    sudo chown -R $USER:$USER /mnt/images
    sudo chmod -R 755 /mnt/images
    
    # Copy docker-compose file if it exists
    if [ -f "docker/docker-compose-vmqa.yml" ]; then
        cp docker/docker-compose-vmqa.yml /var/www/docker-compose.yml
    else
        log "Warning: docker-compose-vmqa.yml not found"
    fi
    
    return 0
}

run_step "setup_directories" step_setup_directories

# ============================================
# STEP 6: Clone/Update Repositories
# ============================================

step_clone_repos() {
    cd /var/www/ || { log "Cannot cd /var/www/"; return 1; }
    
    git clone https://github.com/dp2-eder/back-dp2.git
    git clone https://github.com/dp2-eder/front-dp2.git
    git clone https://github.com/dp2-eder/scrapper-dp2.git
    git clone https://github.com/dp2-eder/front-admin.git
    
    return 0
}

run_step "clone_repos" step_clone_repos

# ============================================
# STEP 7: Build Frontend (Optional)
# ============================================
step_build_frontend() {
    cd /var/www/front-dp2/ || { log "Cannot cd to front-dp2"; return 1; }
    
    # Check if Node.js is available
    if ! command -v node &> /dev/null; then
        log "Node.js not found in system, will use Docker container for build"
        # Pull node image if not exists
        sudo docker pull node:25-alpine || return 1
    fi
    
    # Build using npm if available, otherwise skip (Docker will build it)
    if [ -f "package.json" ]; then
        if command -v npm &> /dev/null; then
            log "Building frontend with system npm..."
            npm install || { log "npm install failed"; return 1; }
            npm run build || { log "npm build failed"; return 1; }
        else
            log "npm not available, frontend will be built during docker compose up"
        fi
    fi
    
    cd /var/www/
    return 0
}

run_step "build_frontend" step_build_frontend

# ============================================
# STEP 8: Copy Environment Files
# ============================================
step_copy_env_files() {
    # Copy .env.example to .env in each repo if .env does not exist
    for repo in back-dp2 front-dp2 scrapper-dp2 front-admin; do
        cd /var/www/ || { log "Cannot cd /var/www/"; return 1; }
        if [ -d "$repo" ]; then
            cd "$repo" || { log "Cannot cd to $repo"; return 1; }
            if [ -f ".env.example" ] && [ ! -f ".env" ]; then
                cp .env.example .env
                log "Copied .env.example to .env in $repo"
            else
                log ".env already exists or .env.example missing in $repo"
            fi
        else
            log "Repository $repo does not exist"
        fi
    done

    return 0
}

run_step "copy_env_files" step_copy_env_files

# ============================================
# STEP 9: Start Docker Compose Services
# ============================================
step_docker_compose_up() {
    cd /var/www/ || { log "Cannot cd /var/www/"; return 1; }
    
    if [ ! -f "docker-compose.yml" ]; then
        log "Error: docker-compose.yml not found in /var/www/"
        return 1
    fi
    
    # Use docker compose (without hyphen for newer versions)
    if sudo docker compose version &>/dev/null; then
        sudo docker compose up -d --build || return 1
    else
        # Fallback to docker-compose (older versions)
        sudo docker-compose up -d --build || return 1
    fi
    
    return 0
}

run_step "docker_compose_up" step_docker_compose_up

# ============================================
# Installation Complete
# ============================================
log "========================================"
log "✓ DP2 QA Environment Installation Complete!"
log "========================================"
log ""
log "Services status:"
sudo docker ps 2>/dev/null || log "Docker containers not running or docker not accessible"
log ""
log "MySQL Database: dp2_qa_db (user: dp2_qa_user)"
log "RabbitMQ vhost: dp2_qa_vhost (user: dp2_qa_user)"
log "Application directory: /var/www/"
log "Images directory: /mnt/images"
log ""
log "To view logs: tail -f $LOG_FILE"
log "To reset installation: sudo rm $CHECKPOINT_FILE"
log ""
