#!/bin/bash
# Script de instalación para VM 3 (Storage/Stateful)
# Ubuntu Server 24.04 LTS
set -e

VM1A_IP="10.0.1.11" # Reemplazar con IP real de VM1A
VM1B_IP="10.0.1.12" # Reemplazar con IP real de VM1B
CHECKPOINT_FILE="/var/lib/dp2/install_vm3.checkpoint"
LOG_FILE="/var/log/dp2_install_vm3.log"
USER_APP="dp2-user"

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
log "Iniciando Instalación VM 3 (Storage)"
log "WebCore IPs permitidas: $VM1A_IP, $VM1B_IP"
log "========================================"

step_system_update() {
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y mysql-server nfs-kernel-server rabbitmq-server curl git
}

run_step "system_update" step_system_update

step_rabbitmq_setup() {
    local RABBITMQ_VHOST="prod_vhost"
    local RABBITMQ_USER="prod_user"
    local RABBITMQ_PASSWORD="prod_password"
    
    sudo apt install -y rabbitmq-server
    sudo systemctl enable rabbitmq-server
    sudo systemctl start rabbitmq-server
    
    # Wait for RabbitMQ to be ready
    if ! sudo rabbitmqctl await_startup --timeout 30000 >/dev/null 2>&1; then
        log "RabbitMQ did not become ready within 30s"
        return 1
    fi
    
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

step_mysql_setup() {
    local DB_NAME="prod"
    local DB_USER="prod_user"
    local DB_PASSWORD="domotica-prod"
    log "  Ejecutando scripts SQL..."
    
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'$VM1A_IP' IDENTIFIED BY '${DB_PASSWORD}';" || return 1
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'$VM1A_IP';" || return 1
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'$VM1B_IP' IDENTIFIED BY '${DB_PASSWORD}';" || return 1
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'$VM1B_IP';" || return 1
    sudo mysql -e "FLUSH PRIVILEGES;" || return 1
    
    log "  Configurando MySQL para escuchar en 0.0.0.0..."
    if [ -f "$MYSQL_CONF_FILE" ]; then
        sudo sed -i "s/^\(bind-address\s*=\s*\)127\.0\.0\.1/\10.0.0.0/" "$MYSQL_CONF_FILE"
        log "  bind-address actualizado en $MYSQL_CONF_FILE"
    else
        log "  Advertencia: No se encontró $MYSQL_CONF_FILE. Omitiendo."
    fi
    
    log "  Reiniciando MySQL para aplicar la configuración..."
    sudo systemctl restart mysql
    sudo systemctl enable mysql

    return 0
}

run_step "mysql_setup" step_mysql_setup

step_nfs_setup() {
    local NFS_DIR="/srv/nfs/images"
    local EXPORTS_FILE="/etc/exports"

    log "  Creando directorio NFS..."
    sudo mkdir -p "$NFS_DIR"
    
    if id "$USER_APP" &>/dev/null; then
        sudo chown "$USER_APP:$USER_APP" "$NFS_DIR"
    else
        log "  Advertencia: Usuario $USER_APP no encontrado. Usando root."
        sudo chown root:root "$NFS_DIR"
    fi
    
    sudo chmod 755 "$NFS_DIR"

    log "  Configurando /etc/exports..."
    
    add_export_line() {
        local ip="$1"
        local config="$NFS_DIR $ip(rw,sync,no_subtree_check)"
        if ! grep -qF "$config" "$EXPORTS_FILE"; then
            echo "$config" | sudo tee -a "$EXPORTS_FILE"
            log "    Agregada regla para $ip"
        else
            log "    Regla para $ip ya existe"
        fi
    }

    add_export_line "$VM1A_IP"
    add_export_line "$VM1B_IP"

    log "  Aplicando exportaciones y reiniciando NFS..."
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server
    
    return 0
}

run_step "nfs_setup" step_nfs_setup

log "========================================"
log "✓ Instalación de VM 3 (Storage) Completada"
log "========================================"
log "Estado de Servicios:"
log "MySQL: $(systemctl is-active mysql)"
log "RabbitMQ: $(systemctl is-active rabbitmq-server)"
log "NFS Server: $(systemctl is-active nfs-kernel-server)"
log ""
log "Recuerda configurar el Firewall (UFW) para permitir conexiones desde:"
log " - $VM1A_IP"
log " - $VM1B_IP"
log "En los puertos: 3306 (MySQL), 2049 (NFS), 5672 (RabbitMQ)"
log ""
