#!/bin/bash
# Script to install a Private Docker Registry on VM
set -e

# Configuration
CHECKPOINT_FILE="/var/lib/dp2/install_registry.checkpoint"
LOG_FILE="/var/log/dp2_install_registry.log"
REGISTRY_DIR="/opt/docker-registry"
REGISTRY_DOMAIN=$(hostname -I | awk '{print $1}') # Uses IP by default. Change to domain if available.
REGISTRY_USER="dp2admin"
REGISTRY_PASS="domotica-prod"

# Setup logs and checkpoints
sudo mkdir -p "$(dirname "$CHECKPOINT_FILE")" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"; }
is_step_done() { [ -f "$CHECKPOINT_FILE" ] && grep -q "^$1$" "$CHECKPOINT_FILE"; }
mark_step_done() { log "✓ Completed: $1"; echo "$1" | sudo tee -a "$CHECKPOINT_FILE" >/dev/null; }

run_step() {
    if is_step_done "$1"; then log "⊳ Skipping: $1"; return 0; fi
    log "▶ Starting: $1"; if "$@"; then mark_step_done "$1"; else log "✗ Failed: $1"; return 1; fi
}

log "=== Starting Docker Private Registry Installation ==="

# --- STEP 1: Install Docker & Tools ---
step_install_base() {
    sudo apt update -y && sudo apt upgrade -y
    sudo apt install -y curl wget apache2-utils
    
    # Install Docker
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
}
run_step "install_base" step_install_base

# --- STEP 2: Prepare Directories & Auth ---
step_setup_auth() {
    sudo mkdir -p "$REGISTRY_DIR/auth"
    sudo mkdir -p "$REGISTRY_DIR/data"
    sudo mkdir -p "$REGISTRY_DIR/certs"
    
    # Create htpasswd file
    log "Creating registry user: $REGISTRY_USER"
    echo "$REGISTRY_PASS" | sudo htpasswd -Bc "$REGISTRY_DIR/auth/htpasswd" "$REGISTRY_USER"
}
run_step "setup_auth" step_setup_auth

# --- STEP 3: Generate Self-Signed SSL ---
# Docker requires HTTPS for registries unless configured as insecure.
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

# --- STEP 4: Create Docker Compose ---
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

# --- STEP 5: Start Registry ---
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
