#!/bin/bash

set -euo pipefail

# --- 1. PARÁMETROS ---
POOL_PATH="/var/lib/libvirt/images/domotica"
VM_NAMES=(
  "vm-lb"
  "vm-1a"
  "vm-1b"
  "vm-2a"
  "vm-3"
)

# --- 2. APAGAR Y ELIMINAR DEFINICIONES ---
for VM in "${VM_NAMES[@]}"; do
    if sudo virsh dominfo "$VM" >/dev/null 2>&1; then
        echo "--- Eliminando VM $VM..."

        # Apaga la VM si está encendida
        if sudo virsh domstate "$VM" | grep -qi running; then
            sudo virsh destroy "$VM" || true
        fi

        # Elimina la definición de libvirt y referencia a NVRAM/firmware
        sudo virsh undefine "$VM" --nvram --snapshots-metadata --remove-all-storage || true
    else
        echo "--- VM $VM no está definida en libvirt."
    fi

    # Borra cualquier qcow2 residual creado por setup.sh
    DISK="$POOL_PATH/$VM.qcow2"
    if [ -f "$DISK" ]; then
        echo "    Borrando disco $DISK"
        sudo rm -f "$DISK"
    fi

done

echo "--- Arquitectura eliminada. ---"
