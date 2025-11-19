#!/bin/bash
# Script de instalación para VM 2x (Worker Nodes)
# Ubuntu Server 24.04 LTS
set -e

CHECKPOINT_FILE="/var/lib/dp2/install_vm2x.checkpoint"
LOG_FILE="/var/log/dp2_install_vm2x.log"

sudo mkdir -p "$(dirname "$CHECKPOINT_FILE")"
sudo mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"
}

is_step_done() {
    [ -f "$CHECKPOINT_FILE" ] && grep -q "^$1$" "$CHECKPOINT_FILE"
}

mark_step_done() {
    log "✓ Completado: $1"
    echo "$1" | sudo tee -a "$CHECKPOINT_FILE" >/dev/null
}

run_step() {
    local step_name="$1"
    shift
    
    if is_step_done "$step_name"; then
        log "⊳ Saltando (ya realizado): $step_name"
        return 0
    fi
    
    log "▶ Iniciando: $step_name"
    if "$@"; then
        mark_step_done "$step_name"
        return 0
    else
        log "✗ Falló: $step_name"
        return 1
    fi
}

log "========================================"
log "Iniciando Instalación VM 2x (Worker)"
log "========================================"

step_system_update() {
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y curl wget build-essential git
}

run_step "system_update" step_system_update

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
    
    return 0
}

run_step "docker_install" step_docker_install

log "========================================"
log "✓ Instalación de VM 2x (Worker) Completada"
log "========================================"
log "Versiones instaladas:"
log "Docker: $(docker --version)"
log ""
log "Nota: Es recomendable reiniciar la sesión o el servidor para aplicar los permisos de grupo Docker."
log ""
