#!/bin/bash

# --- 1. PARÁMETROS (Modifica según necesites) ---
BASE_IMG_SOURCE="noble-server-cloudimg-amd64.img" 
# Ya no necesitamos un USER_DATA_PATH global

# Pool de almacenamiento (donde se guardarán los discos de las VMs)
POOL_NAME="domotica_pool"
POOL_PATH="/var/lib/libvirt/images/domotica"

# --- 2. VALIDACIONES Y NORMALIZACIÓN DE RUTAS ---
if [ ! -f "$BASE_IMG_SOURCE" ]; then
    echo "No se encontró la imagen base en $BASE_IMG_SOURCE"
    exit 1
fi
BASE_IMG_SOURCE_REALPATH="$(realpath "$BASE_IMG_SOURCE")" ###
BASE_IMG_NAME=$(basename "$BASE_IMG_SOURCE_REALPATH") ###
BASE_IMG_POOL_PATH="$POOL_PATH/$BASE_IMG_NAME" ###

# --- 3. CREAR POOL DE ALMACENAMIENTO (si no existe) ---
# (Tu código para crear el pool es correcto, déjalo como está)
sudo mkdir -p $POOL_PATH
if ! sudo virsh pool-list --all | grep -q $POOL_NAME; then
    echo "Creando pool de almacenamiento '$POOL_NAME'..."
    sudo virsh pool-define-as $POOL_NAME dir --target $POOL_PATH
    sudo virsh pool-build $POOL_NAME
    sudo virsh pool-start $POOL_NAME
    sudo virsh pool-autostart $POOL_NAME
else
    echo "Pool de almacenamiento '$POOL_NAME' ya existe."
fi

echo "Copiando la imagen base a $BASE_IMG_POOL_PATH..." ###
sudo cp "$BASE_IMG_SOURCE_REALPATH" "$BASE_IMG_POOL_PATH" ###
sudo chmod 644 "$BASE_IMG_POOL_PATH" ### (Asegura que sea legible)
# Uso: crear_vm <nombre> <ram_mb> <vcpus> <disk_gb> <user_data_file> <red_extra_flags>
crear_vm() {
    NAME=$1
    RAM=$2
    VCPUS=$3
    DISK_SIZE=$4
    USER_DATA_FILE=$5  # <-- Argumento 5: Archivo user-data específico
    EXTRA_NET_FLAGS=$6 # <-- Argumento 6: Redes adicionales
    
    DISK_PATH="$POOL_PATH/$NAME.qcow2"

    # --- Validar User Data ---
    if [ ! -f "$USER_DATA_FILE" ]; then
        echo "Error: No se encontró user-data file en $USER_DATA_FILE"
        return 1
    fi
    USER_DATA_FILE_REALPATH=$(realpath $USER_DATA_FILE)


    echo "--- Creando disco para $NAME..."
    # 1. Crea un disco nuevo que usa la imagen base (clon)
    sudo qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG_POOL_PATH" "$DISK_PATH"
    
    # 2. Redimensiona el disco a su tamaño final
    sudo qemu-img resize "$DISK_PATH" $DISK_SIZE

    # --- Cloud-Init Metadata ---
    CI_TMP_DIR=$(mktemp -d)
    META_DATA_PATH="$CI_TMP_DIR/meta-data"
    cat <<EOF > "$META_DATA_PATH"
instance-id: $NAME-$(date +%s)
local-hostname: $NAME
EOF

    echo "--- Lanzando VM $NAME con virt-install..."
    # 3. Lanza la VM
    sudo virt-install \
        --name $NAME \
        --ram $RAM \
        --vcpus $VCPUS \
        --os-variant ubuntunoble \
        --disk path=$DISK_PATH,bus=virtio \
        --network network=domotica-net,model=virtio \
        $EXTRA_NET_FLAGS \
        --cloud-init user-data=$USER_DATA_FILE_REALPATH,meta-data=$META_DATA_PATH \
        --graphics none \
        --noautoconsole \
        --import
    
    echo "--- VM $NAME creada."

    rm -rf "$CI_TMP_DIR"
}

# --- 5. LANZAR ARQUITECTURA (MODIFICADO) ---
# Las llamadas ahora pasan el archivo user-data correcto

crear_vm "vm-lb" 1024 1 "10G" "user-data-vm-lb.yaml" "--network network=default,model=virtio"
crear_vm "vm-1a" 2048 2 "10G" "user-data-vm-1a.yaml" ""
crear_vm "vm-1b" 2048 2 "10G" "user-data-vm-1b.yaml" ""
crear_vm "vm-2a" 2048 2 "10G" "user-data-vm-2a.yaml" ""
crear_vm "vm-3"  2048 2 "10G" "user-data-vm-3.yaml"  ""

# crear_vm "vm-qa" 4196 4 "20G" "user-data-vm-qa.yaml" "--network network=default,model=virtio"

echo "--- ¡Arquitectura desplegada! ---"
echo "Las VMs están arrancando y auto-configurando sus IPs."
echo "En 2 minutos, deberías poder ejecutar tu playbook de Ansible."
