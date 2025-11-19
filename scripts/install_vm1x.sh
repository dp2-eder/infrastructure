#!/bin/bash
# Script de instalación para VM 1x (WebCore Nodes)
# Ubuntu Server 24.04 LTS
set -e

VM3_IP="10.0.1.30" # Reemplazar con IP real de VM3
CHECKPOINT_FILE="/var/lib/dp2/install_vm1x.checkpoint"
LOG_FILE="/var/log/dp2_install_vm1x.log"

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
log "Iniciando Instalación VM 1x (WebCore)"
log "Target NFS Server: $VM3_IP"
log "========================================"

step_system_update() {
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y curl wget build-essential git nfs-common
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

step_nfs_client() {
    local MOUNT_POINT="/mnt/images"
    local NFS_SHARE="$VM3_IP:/srv/nfs/images"
    
    log "  Creando punto de montaje: $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
    
    if ! grep -q "$NFS_SHARE" /etc/fstab; then
        log "  Agregando entrada a /etc/fstab..."
        echo "$NFS_SHARE  $MOUNT_POINT  nfs  auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0" | sudo tee -a /etc/fstab
    else
        log "  Entrada fstab ya existe."
    fi
    
    log "  Montando volumen..."
    if sudo mount -a; then
        log "  Montaje exitoso."
        df -h | grep "$MOUNT_POINT"
    else
        log "  ⚠ ADVERTENCIA: No se pudo montar NFS. Verifique que VM3 ($VM3_IP) esté encendida y configurada."
        # No se retorna 1 para permitir que el script termine, 
        # ya que esto puede arreglarse después reiniciando o con 'mount -a'
    fi
}

run_step "nfs_client" step_nfs_client

log "========================================"
log "✓ Instalación de VM 1x (WebCore) Completada"
log "========================================"
log "Versiones instaladas:"
log "Docker: $(docker --version)"
log ""
log "Estado de NFS:"
if mount | grep -q "/mnt/images"; then
    log "✅ NFS Montado correctamente."
else
    log "❌ NFS NO montado. Revise la conexión con VM3 ($VM3_IP)."
