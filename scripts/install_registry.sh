#!/bin/bash
# Script to install a Private Docker Registry on VM
set -e

# Configuration
CHECKPOINT_FILE="/var/lib/dp2/install_registry.checkpoint"
LOG_FILE="/var/log/dp2_install_registry.log"
REGISTRY_DIR="/opt/docker-registry"
REGISTRY_DOMAIN="10.0.1.10" # Use the VM's IP address or domain name
REGISTRY_MAIN_USER="dp2-user"
REGISTRY_MAIN_PASS="domotica-prod"

REGISTRY_USER="manolo"
REGISTRY_PASS="h0l@!Mundo"

# Setup logs and checkpoints
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

log "=== Starting Docker Private Registry Installation ==="

# --- STEP 1: Update System ---
step_system_update() {
    sudo apt update -y
    sudo apt upgrade -y
    # apache2-utils is needed for htpasswd
    sudo apt install apache2-utils apt-transport-https ca-certificates curl software-properties-common -y
}

run_step "system_update" step_system_update

# --- STEP 2: Docker Install ---
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

# ----------------------------------------------------
# --- STEP 3: Configure Auth and Run Registry ---
# ----------------------------------------------------
step_configure_auth_and_start_registry() {
    log "Setting up Registry directories and htpasswd..."
    
    # 1. Create directories for data and auth persistence
    sudo mkdir -p "$REGISTRY_DIR/data"
    sudo mkdir -p "$REGISTRY_DIR/auth"
    local htpasswd_file="$REGISTRY_DIR/auth/htpasswd"
    
    sudo htpasswd -Bc "$htpasswd_file" "$REGISTRY_MAIN_USER" "$REGISTRY_MAIN_PASS"
    log "htpasswd file created for user $REGISTRY_MAIN_USER."

    sudo htpasswd -B "$htpasswd_file" "$REGISTRY_USER" "$REGISTRY_PASS"

    # 3. Stop and remove any existing registry container
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^registry$"; then
        log "Stopping and removing old 'registry' container..."
        sudo docker stop registry || true
        sudo docker rm registry || true
    fi

    # 4. Start the new container with persistence and htpasswd authentication
    log "Starting Docker Registry with htpasswd authentication on port 5000..."
    
    sudo docker run -d \
      -p 5000:5000 \
      --restart=always \
      --name registry \
      -v "$REGISTRY_DIR/data":/var/lib/registry \
      -v "$REGISTRY_DIR/auth":/auth \
      -e REGISTRY_AUTH=htpasswd \
      -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
      -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
      registry:2
    
}

run_step "configure_auth_and_start_registry" step_configure_auth_and_start_registry

log "=== Registry Installation Complete ==="
log "Registry URL: http://$REGISTRY_DOMAIN:5000"
log "NOTE: This registry is running on HTTP (Insecure) and requires client configuration."
log ""
log "To push images, tag them as follows:"
log "  docker tag <image> $REGISTRY_DOMAIN:5000/<image>"
log "Then push using:"
log "  docker push $REGISTRY_DOMAIN:5000/<image>"
log "========================================"