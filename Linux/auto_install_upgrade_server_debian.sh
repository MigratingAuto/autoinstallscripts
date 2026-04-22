#!/bin/bash
#
# auto_install_upgrade_server_debian.sh
#
# Purpose: Bootstrap a fresh Debian or Ubuntu VM running on Proxmox.
#   - Updates all packages
#   - Installs net-tools and qemu-guest-agent
#   - Enables the QEMU guest agent service
#   - Loads the virtio_balloon kernel module (for Proxmox memory ballooning)
#   - Installs and enables openssh-server
#   - Installs and configures ufw to allow SSH
#   - Pulls SSH public keys from GitHub (user: migratingauto)
#   - Hardens SSH by disabling password authentication (keys only)
#
# Target OS: Debian 12+ / Ubuntu 22.04+ (works on any modern Debian-family)
# Package Manager: apt
# Usage: Run as a regular user with sudo privileges (NOT as root directly).
#        sudo ./auto_install_upgrade_server_debian.sh
#
# IMPORTANT: This script will disable SSH password authentication.
#            It includes a safety check to verify keys were successfully
#            pulled from GitHub before modifying sshd_config. If the key
#            pull fails, SSH hardening is skipped to prevent lockout.
#
# TEMPLATE USE: If this VM will be cloned as a Proxmox template, uncomment
#               the "TEMPLATE PREP" section at the bottom to regenerate
#               SSH host keys on first boot of each clone.
#

set -euo pipefail  # Exit on error, undefined var, or pipe failure

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
GITHUB_USER="migratingauto"
GITHUB_KEYS_URL="https://github.com/${GITHUB_USER}.keys"

# Non-interactive apt - prevents prompts during package install/upgrade
export DEBIAN_FRONTEND=noninteractive

# Determine the target user (the user who invoked sudo, or current user)
if [[ -n "${SUDO_USER:-}" ]]; then
    TARGET_USER="${SUDO_USER}"
    TARGET_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    TARGET_USER="${USER}"
    TARGET_HOME="${HOME}"
fi

SSH_DIR="${TARGET_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

# Detect distro for any conditional behavior
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-unknown}"
else
    DISTRO_ID="unknown"
    DISTRO_NAME="unknown"
fi

echo "=========================================="
echo "Debian/Ubuntu Proxmox VM Bootstrap Script"
echo "Detected distro: ${DISTRO_NAME}"
echo "Target user: ${TARGET_USER}"
echo "Target home: ${TARGET_HOME}"
echo "=========================================="

# ----------------------------------------------------------------------
# Step 1: Update package index and upgrade all packages
# ----------------------------------------------------------------------
echo ""
echo "[1/8] Updating system packages..."
sudo apt update
sudo apt upgrade -y

# ----------------------------------------------------------------------
# Step 2: Install required packages
# ----------------------------------------------------------------------
echo ""
echo "[2/8] Installing net-tools, qemu-guest-agent, openssh-server, ufw, curl..."
sudo apt install -y net-tools qemu-guest-agent openssh-server ufw curl ca-certificates

# ----------------------------------------------------------------------
# Step 3: Enable and start the QEMU guest agent
# ----------------------------------------------------------------------
echo ""
echo "[3/8] Enabling qemu-guest-agent service..."

# On modern Debian/Ubuntu, qemu-guest-agent is started by a udev rule
# when the virtio-serial device appears. The unit itself has no [Install]
# section, so 'systemctl enable' returns non-zero -- which would kill the
# script under 'set -e'. We try to enable it (harmless on older systems
# that DO have [Install]) but don't fail if it can't be enabled.
if sudo systemctl enable qemu-guest-agent 2>/dev/null; then
    echo "  -> qemu-guest-agent enabled via systemd"
else
    echo "  -> qemu-guest-agent has no [Install] section (expected on modern Debian/Ubuntu)"
    echo "  -> It will be started automatically by udev when the virtio device appears"
fi

# Try to start it now if the virtio device is already present
# (i.e., QEMU Guest Agent is already enabled in Proxmox for this VM).
if [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
    sudo systemctl start qemu-guest-agent || true
    if systemctl is-active --quiet qemu-guest-agent; then
        echo "  -> qemu-guest-agent is running"
    else
        echo "  !! qemu-guest-agent did not start -- check 'systemctl status qemu-guest-agent'"
    fi
else
    echo "  -> virtio-serial device not present yet"
    echo "  -> Enable QEMU Guest Agent in Proxmox (VM -> Options) and power-cycle the VM"
fi

# ----------------------------------------------------------------------
# Step 4: Enable and start sshd
# ----------------------------------------------------------------------
echo ""
echo "[4/8] Enabling ssh service..."
# Note: On Debian/Ubuntu the service is called 'ssh', not 'sshd'.
# The 'sshd' alias works on most modern systemd installs but 'ssh' is canonical.
sudo systemctl enable --now ssh

# Verify ssh is actually running before proceeding
if ! systemctl is-active --quiet ssh; then
    echo "  !! ERROR: ssh failed to start"
    sudo systemctl status ssh --no-pager
    exit 1
fi
echo "  -> ssh is running"

# ----------------------------------------------------------------------
# Step 5: Configure ufw to allow SSH
# ----------------------------------------------------------------------
echo ""
echo "[5/8] Configuring ufw for SSH..."

# Allow SSH BEFORE enabling ufw - critical to avoid being locked out
# of remote sessions when the firewall activates.
if sudo ufw status | grep -qE '^(22|OpenSSH)\b.*ALLOW'; then
    echo "  -> SSH already allowed in ufw"
else
    sudo ufw allow OpenSSH
    echo "  -> SSH allowed in ufw"
fi

# Enable ufw if it's not already active.
# The 'echo y |' bypasses the interactive "are you sure?" prompt.
if sudo ufw status | grep -q "Status: active"; then
    echo "  -> ufw already active"
else
    echo "y" | sudo ufw enable
    echo "  -> ufw enabled and will start at boot"
fi

# ----------------------------------------------------------------------
# Step 6: Load the virtio_balloon kernel module
# ----------------------------------------------------------------------
echo ""
echo "[6/8] Loading virtio_balloon kernel module..."

# Check if the module is already loaded (or built into the kernel).
# Some Proxmox guest kernels build virtio_balloon in rather than as a
# loadable module, in which case modprobe will fail under 'set -e'.
if lsmod | grep -q '^virtio_balloon'; then
    echo "  -> virtio_balloon already loaded"
elif sudo modprobe virtio_balloon 2>/dev/null; then
    echo "  -> virtio_balloon loaded"
else
    # Module is either built-in (already active) or genuinely unavailable.
    # Check /proc/modules and /sys to figure out which.
    if [[ -d /sys/module/virtio_balloon ]]; then
        echo "  -> virtio_balloon is built into the kernel (no module to load)"
    else
        echo "  !! WARNING: virtio_balloon could not be loaded and is not built-in"
        echo "  !! Proxmox memory ballooning may not work for this VM"
    fi
fi

# Make it persistent across reboots.
# Debian/Ubuntu support BOTH /etc/modules (legacy) and /etc/modules-load.d/ (modern).
# Using the modern systemd-style location for consistency with other distros.
echo "virtio_balloon" | sudo tee /etc/modules-load.d/virtio_balloon.conf >/dev/null
echo "  -> virtio_balloon will auto-load at boot (if not built-in)"

# ----------------------------------------------------------------------
# Step 7: Pull SSH public keys from GitHub
# ----------------------------------------------------------------------
echo ""
echo "[7/8] Pulling SSH keys from GitHub user '${GITHUB_USER}'..."

# Ensure .ssh directory exists with correct permissions
sudo -u "${TARGET_USER}" mkdir -p "${SSH_DIR}"
sudo chmod 700 "${SSH_DIR}"
sudo chown "${TARGET_USER}:${TARGET_USER}" "${SSH_DIR}"

# Download keys to a temporary file first so we can validate before replacing
TEMP_KEYS=$(mktemp)
trap 'rm -f "${TEMP_KEYS}"' EXIT

KEYS_PULLED=false
if curl -fsSL --connect-timeout 10 "${GITHUB_KEYS_URL}" -o "${TEMP_KEYS}"; then
    # Verify the file is non-empty and looks like SSH keys
    if [[ -s "${TEMP_KEYS}" ]] && grep -qE '^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-) ' "${TEMP_KEYS}"; then
        KEY_COUNT=$(grep -cE '^(ssh-|ecdsa-)' "${TEMP_KEYS}")
        echo "  -> Found ${KEY_COUNT} valid SSH key(s) on GitHub"

        # Replace authorized_keys with the pulled keys
        sudo cp "${TEMP_KEYS}" "${AUTH_KEYS}"
        sudo chmod 600 "${AUTH_KEYS}"
        sudo chown "${TARGET_USER}:${TARGET_USER}" "${AUTH_KEYS}"

        echo "  -> Wrote ${KEY_COUNT} key(s) to ${AUTH_KEYS}"
        KEYS_PULLED=true
    else
        echo "  !! WARNING: Downloaded file is empty or doesn't contain valid SSH keys"
        echo "  !! Check that https://github.com/${GITHUB_USER} has public SSH keys configured"
    fi
else
    echo "  !! ERROR: Failed to fetch keys from ${GITHUB_KEYS_URL}"
    echo "  !! Check your internet connection and that the GitHub user exists"
fi

# ----------------------------------------------------------------------
# Step 8: Harden SSH configuration (only if keys were successfully pulled)
# ----------------------------------------------------------------------
echo ""
echo "[8/8] SSH hardening..."

if [[ "${KEYS_PULLED}" == "true" ]]; then
    SSHD_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"

    echo "  -> Creating drop-in config at ${SSHD_DROPIN}"
    sudo tee "${SSHD_DROPIN}" >/dev/null <<EOF
# Managed by auto_install_upgrade_server_debian.sh
# Disable password authentication - SSH key auth only
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

    # Validate the config before restarting sshd
    if sudo sshd -t; then
        sudo systemctl restart ssh
        echo "  -> SSH password authentication DISABLED"
        echo "  -> ssh restarted successfully"
    else
        echo "  !! ERROR: sshd config validation failed - removing drop-in file"
        sudo rm -f "${SSHD_DROPIN}"
        echo "  !! SSH config was NOT changed"
        exit 1
    fi
else
    echo "  !! SKIPPED: SSH hardening skipped because keys were not pulled successfully"
    echo "  !! This prevents you from being locked out of the VM"
    echo "  !! Fix the key issue and re-run the script, or harden SSH manually"
fi

# ----------------------------------------------------------------------
# OPTIONAL: TEMPLATE PREP
# ----------------------------------------------------------------------
# Uncomment this section if this VM will be converted to a Proxmox
# template that gets cloned. It creates a systemd service that
# regenerates SSH host keys on first boot of each clone. Without this,
# every clone would share the same SSH host keys, which is a security
# risk and causes "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings on
# the client.
#
# echo ""
# echo "[TEMPLATE PREP] Setting up SSH host key regeneration on first boot..."
#
# sudo tee /etc/systemd/system/regenerate-ssh-host-keys.service >/dev/null <<'EOF'
# [Unit]
# Description=Regenerate SSH host keys on first boot
# Before=ssh.service
# ConditionFileNotEmpty=!/etc/ssh/ssh_host_ed25519_key
#
# [Service]
# Type=oneshot
# ExecStart=/usr/bin/ssh-keygen -A
# ExecStartPost=/bin/systemctl disable regenerate-ssh-host-keys.service
#
# [Install]
# WantedBy=multi-user.target
# EOF
#
# sudo systemctl enable regenerate-ssh-host-keys.service
#
# echo "  -> regenerate-ssh-host-keys.service enabled"
# echo "  -> Before converting to template, run: sudo rm -f /etc/ssh/ssh_host_*"
# echo "  -> Then shutdown and convert in Proxmox"

# ----------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Bootstrap complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - System packages updated"
echo "  - qemu-guest-agent installed and running"
echo "  - openssh-server installed and running"
echo "  - ufw installed, configured, and active (SSH allowed)"
echo "  - virtio_balloon module loaded (and persistent)"
if [[ "${KEYS_PULLED}" == "true" ]]; then
    echo "  - SSH keys pulled from GitHub user: ${GITHUB_USER}"
    echo "  - SSH password authentication: DISABLED"
else
    echo "  - SSH keys: NOT configured (check errors above)"
    echo "  - SSH password authentication: still enabled"
fi
echo ""
echo "Reminder: Enable the QEMU Guest Agent in Proxmox:"
echo "  VM -> Options -> QEMU Guest Agent -> Enable"
echo "  Then fully power-cycle (not reboot) the VM."
echo ""
