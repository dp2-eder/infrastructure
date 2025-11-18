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
    sudo apt install -y git curl wget build-essential
    curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
    sudo apt install -y nodejs
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

# --- STEP 3: Prepare Directories & Auth ---
step_setup_auth() {
    sudo mkdir -p "$REGISTRY_DIR/auth"
    sudo mkdir -p "$REGISTRY_DIR/data"
    sudo mkdir -p "$REGISTRY_DIR/certs"
    
    # Create htpasswd file
    log "Creating registry user: $REGISTRY_USER"
    echo "$REGISTRY_PASS" | sudo htpasswd -Bc "$REGISTRY_DIR/auth/htpasswd" "$REGISTRY_USER"
}
run_step "setup_auth" step_setup_auth

# --- STEP 4: Generate Self-Signed SSL ---
step_generate_certs() {
    log "Generating self-signed certificate for IP: $REGISTRY_DOMAIN"
    
    sudo openssl req -newkey rsa:4096 -nodes -sha256 -keyout "$REGISTRY_DIR/certs/domain.key" \
        -x509 -days 365 -out "$REGISTRY_DIR/certs/domain.crt" \
        -subj "/C=PE/ST=Lima/L=Lima/O=DP2/CN=$REGISTRY_DOMAIN"
        
    # Trust the certificate locally (for testing curl/docker on this VM)
    sudo cp "$REGISTRY_DIR/certs/domain.crt" /usr/local/share/ca-certificates/registry.crt
    sudo update-ca-certificates
    
    # Configure Docker daemon to trust this registry if needed (optional but helpful)
    # We avoid modifying daemon.json blindly to not break existing configs.
}
run_step "generate_certs" step_generate_certs

# --- STEP 5: Create Docker Compose ---
step_create_compose() {
    cat <<EOF | sudo tee "$REGISTRY_DIR/docker-compose.yml"
services:
  registry:
    image: registry:2
    restart: always
    container_name: dp2-registry
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/domain.crt
      REGISTRY_HTTP_TLS_KEY: /certs/domain.key
    volumes:
      - ./data:/var/lib/registry
      - ./auth:/auth
      - ./certs:/certs

  # Optional: Web UI to view images
  registry-ui:
    image: joxit/docker-registry-ui:static
    restart: always
    ports:
      - "8080:80"
    environment:
      - REGISTRY_URL=https://${REGISTRY_DOMAIN}:5000
      - REGISTRY_TITLE=DP2 Registry
EOF
}
run_step "create_compose" step_create_compose

# --- STEP 6: Start Registry ---
step_start_registry() {
    cd "$REGISTRY_DIR"
    sudo docker compose up -d
}
run_step "start_registry" step_start_registry

log "=== Registry Installation Complete ==="
log "Registry URL: https://$REGISTRY_DOMAIN:5000"
log "Web UI URL:   http://$REGISTRY_DOMAIN:8080"
log "Credentials:  $REGISTRY_USER / (hidden)"
log ""
