# Domotica Infrastructure Automation

This directory contains an Ansible configuration that provisions the lab environment described in the VM templates. It complements the existing `setup.sh` workflow by automating the post-creation configuration of every virtual machine.

## Layout

- `ansible.cfg` – Ansible defaults tuned for this project.
- `inventory.ini` – Static inventory with the VM IP assignments for the lab VMs.
- `group_vars/` – Shared variables for networking, credentials, and host group specifics.
- `playbooks/site.yml` – Entry-point playbook orchestrating all roles.
- `roles/` – Individual roles for shared package setup, NAT packages, Docker/NFS clients for web nodes, workers, and the storage/database node.
- `requirements.yml` – Collections needed (install with `ansible-galaxy collection install -r requirements.yml`).

## Usage

1. Install Ansible and the required collections on the control node:
   ```bash
   sudo dnf install ansible-core
   ansible-galaxy collection install -r requirements.yml
   ```
2. Run the site playbook once the VMs are reachable via SSH:
   ```bash
   ansible-playbook -i inventory.ini playbooks/site.yml
   ```

Re-running the playbook is safe thanks to idempotent tasks and will converge each VM to the desired state.
