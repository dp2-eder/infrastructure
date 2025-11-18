#!/bin/bash
# Script to install a Private Docker Registry on VM
set -e

# Configuration
CHECKPOINT_FILE="/var/lib/dp2/install_registry.checkpoint"
LOG_FILE="/var/log/dp2_install_registry.log"
REGISTRY_DIR="/opt/docker-registry"
REGISTRY_DOMAIN="10.0.1.10" # Use the VM's IP address or domain name
REGISTRY_USER="dp2admin"
REGISTRY_PASS="domotica-prod"

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
    sudo apt install apache2-utils apt-transport-https ca-certificates curl software-properties-common -y
}

run_step "system_update" step_system_update

# --- STEP 2: Dicker Install ---
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


# --- STEP 3: Start Registry ---
step_start_registry() {
    docker run -d -p 5000:5000 --restart=always --name registry registry:2
}
run_step "start_registry" step_start_registry

log "=== Registry Installation Complete ==="
log "Registry URL: https://$REGISTRY_DOMAIN:5000"
log "Web UI URL:   http://$REGISTRY_DOMAIN:8080"
log "Credentials:  $REGISTRY_USER / (hidden)"
log ""
