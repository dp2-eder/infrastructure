#!/bin/bash
# This script is only for Ubuntu systems
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y git curl wget build-essential nginx

# MySQL installation
sudo apt install -y mysql-server
sudo systemctl start mysql
sudo systemctl enable mysql

# Create a default database and user
DB_NAME="dp2_qa_db"
DB_USER="dp2_qa_user"
DB_PASSWORD="dp2_qa_password"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# RabbitMQ installation
sudo apt install -y rabbitmq-server
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server
sudo rabbitmq-plugins enable --offline rabbitmq_management

# RabbitMQ default vhost and user for QA
RABBITMQ_VHOST="dp2_qa_vhost"
RABBITMQ_USER="dp2_qa_user"
RABBITMQ_PASSWORD="dp2_qa_password"
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

# Docker installation
# Add Docker's official GPG key:
sudo apt update -y
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -y

# Install Docker Engine, CLI, and Containerd
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Post-installation steps
sudo usermod -aG docker $USER

# setup /var/www/
sudo mkdir -p /var/www/
sudo chown -R $USER:$USER /var/www/
sudo chmod -R 755 /var/www/
cp docker/docker-qa-compose.yml /var/www/docker-compose.yml
cd /var/www/ || { echo "Cannot cd /var/www/"; exit 1; }

clone_or_update() {
    local url="$1" dir="$2"
    if [ -d "$dir" ]; then
        if [ -d "$dir/.git" ]; then
            echo "Updating existing repo $dir..."
            git -C "$dir" fetch --all --prune || { echo "git fetch failed for $dir"; exit 1; }
            # Try a safe pull; prefer resetting to remote HEAD to avoid local conflicts
            git -C "$dir" reset --hard origin/HEAD >/dev/null 2>&1 || git -C "$dir" pull || { echo "Failed to update $dir"; exit 1; }
        else
            timestamp=$(date +%s)
            echo "Directory $dir exists but is not a git repo. Backing up to ${dir}.bak.$timestamp"
            mv "$dir" "${dir}.bak.$timestamp" || { echo "Failed to backup $dir"; exit 1; }
            echo "Cloning $url into $dir..."
            git clone "$url" "$dir" || { echo "Failed to clone $url"; exit 1; }
        fi
    else
        echo "Cloning $url into $dir..."
        git clone "$url" "$dir" || { echo "Failed to clone $url"; exit 1; }
    fi
}

clone_or_update https://github.com/dp2-eder/back-dp2.git back-dp2
clone_or_update https://github.com/dp2-eder/front-dp2.git front-dp2
clone_or_update https://github.com/dp2-eder/scrapper-dp2.git scrapper-dp2
clone_or_update https://github.com/dp2-eder/front-admin.git front-admin

sudo mkdir -p /mnt/images
sudo chown -R $USER:$USER /mnt/images
sudo chmod -R 755 /mnt/images
