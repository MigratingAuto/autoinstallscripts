# autoinstallscripts

Bootstrap scripts for fresh Linux VMs running on Proxmox. These scripts handle the tedious first-boot tasks — package updates, guest agent install, SSH setup, and basic hardening — so you can get to the actual work faster.

## What the Scripts Do

Both scripts perform the same core tasks, adapted to their respective package manager and distro conventions:

1. Update and upgrade all system packages
2. Install `net-tools` and `qemu-guest-agent` for Proxmox integration
3. Enable the QEMU guest agent service (for graceful shutdowns, IP reporting, snapshot freeze/thaw)
4. Install and enable `openssh-server`
5. Configure the firewall to allow SSH
6. Load the `virtio_balloon` kernel module (for Proxmox memory ballooning)
7. Pull SSH public keys from GitHub (user: `migratingauto`)
8. Harden SSH by disabling password authentication

## Available Scripts

| Script | Target OS | Package Manager | Firewall |
|--------|-----------|-----------------|----------|
| [`Linux/auto_install_upgrade_server_fedora.sh`](Linux/auto_install_upgrade_server_fedora.sh) | Fedora (latest) | `dnf` | `firewalld` |
| [`Linux/auto_install_upgrade_server_debian.sh`](Linux/auto_install_upgrade_server_debian.sh) | Debian 12+ / Ubuntu 22.04+ | `apt` | `ufw` |

## Prerequisites

Before running either script:

- A fresh VM with the target OS installed and network connectivity
- A regular user account with `sudo` privileges (do **not** run as root directly)
- SSH public keys published on your GitHub profile at `https://github.com/migratingauto.keys`
  - To add keys: GitHub → Settings → SSH and GPG keys → New SSH key
- For Proxmox guests: the QEMU Guest Agent should also be enabled on the VM in Proxmox
  - **VM → Options → QEMU Guest Agent → Enable**
  - Then **fully power-cycle** the VM (not just reboot) for the change to take effect

## Quick Start

### Fedora

```bash
curl -fsSL -o bootstrap.sh \
  https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_fedora.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

### Debian / Ubuntu

```bash
curl -fsSL -o bootstrap.sh \
  https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_debian.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

> **Note:** On minimal Debian installs, `curl` may not be present by default. If `curl` is missing, install it first with `sudo apt install -y curl` or substitute `wget`:
> ```bash
> wget -O bootstrap.sh https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_debian.sh
> ```

## Recommended Workflow

The scripts disable SSH password authentication as their final step, so a wrong move could lock you out of the VM. Follow this order to stay safe:

1. **Verify your GitHub keys are published:**
   Open `https://github.com/migratingauto.keys` in a browser. You should see plain-text key data. If the page is empty, add keys to your GitHub account first.

2. **Have a fallback console open:**
   Keep the Proxmox VM console (noVNC) open in another tab. If SSH breaks, you can still get in.

3. **Download and review the script:**
   ```bash
   curl -fsSL -o bootstrap.sh https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_fedora.sh
   less bootstrap.sh
   ```
   Always inspect scripts pulled from the internet before running them with `sudo`.

4. **Run the script:**
   ```bash
   chmod +x bootstrap.sh
   sudo ./bootstrap.sh
   ```

5. **Test SSH from another terminal BEFORE closing the current session:**
   ```bash
   ssh user@<vm-ip>
   ```
   If key-based login works, you're done. If not, you still have the original session and the Proxmox console as fallbacks.

## Safety Features

Both scripts include the following safeguards:

- **`set -euo pipefail`** — Strict bash mode. The script aborts on any error, undefined variable, or failed pipe.
- **GitHub key validation** — Keys are downloaded to a temp file and validated before replacing `authorized_keys`. The script checks that the file is non-empty and contains valid SSH key formats (`ssh-rsa`, `ssh-ed25519`, `ecdsa-sha2-*`).
- **SSH hardening gate** — If the GitHub key pull fails for any reason, the SSH hardening step is automatically **skipped**. Password authentication stays enabled so you don't get locked out.
- **`sshd -t` config validation** — The drop-in SSH config is syntax-checked before sshd is restarted. If validation fails, the drop-in file is removed and the original config is preserved.
- **Sudo user detection** — Detects the actual user via `SUDO_USER` (not `$HOME`, which would resolve to `/root` under sudo) so SSH keys land in the correct user's home directory.
- **Idempotent firewall checks** — Re-running the script won't create duplicate firewall rules.

## Customization

### Change the GitHub username

Both scripts read keys from a hardcoded GitHub user. To use a different account, edit the `GITHUB_USER` variable near the top of the script:

```bash
GITHUB_USER="your-github-username"
```

### Skip SSH hardening

If you want to keep password auth enabled (e.g., for shared development VMs), comment out or remove the entire **Step 8: Harden SSH configuration** block.

### Use as a Proxmox VM template

Both scripts include a commented-out **TEMPLATE PREP** section near the bottom. If you plan to convert the VM to a Proxmox template that gets cloned, uncomment that block before running the script. It installs a one-shot systemd service that regenerates SSH host keys on first boot of each clone — preventing every clone from sharing the same host keys.

After running the script with template prep enabled:

```bash
# Final cleanup before converting to template:
sudo rm -f /etc/ssh/ssh_host_*
sudo cloud-init clean  # if using cloud-init
sudo shutdown -h now
```

Then in Proxmox: **VM → More → Convert to template**.

## Troubleshooting

### "Failed to fetch keys from GitHub"

- Check internet connectivity from the VM: `curl -I https://github.com`
- Confirm the GitHub user has public SSH keys: `curl https://github.com/migratingauto.keys`
- Check DNS: `nslookup github.com`

### "sshd config validation failed"

- The script removes the bad config automatically and exits. SSH will continue working with the previous config.
- Run `sudo sshd -t` manually to see the specific error.
- Inspect the file the script tried to create: `sudo cat /etc/ssh/sshd_config.d/99-hardening.conf` (if it still exists).

### Locked out after running

- Connect via the Proxmox VM console (noVNC).
- Re-enable password auth temporarily: `sudo rm /etc/ssh/sshd_config.d/99-hardening.conf && sudo systemctl restart ssh` (or `sshd` on Fedora).
- Investigate why your SSH keys aren't working before re-hardening.

### QEMU Guest Agent not reporting in Proxmox

- Verify the agent is running on the VM: `systemctl status qemu-guest-agent`
- Verify it's enabled in Proxmox: **VM → Options → QEMU Guest Agent**
- A full power-cycle (not reboot) is required after enabling in Proxmox.

## Documentation Links

- [Proxmox QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
- [Fedora dnf documentation](https://docs.fedoraproject.org/en-US/quick-docs/dnf/)
- [Debian apt documentation](https://wiki.debian.org/Apt)
- [systemd modules-load.d](https://www.freedesktop.org/software/systemd/man/modules-load.d.html)
- [sshd_config man page](https://man.openbsd.org/sshd_config)
- [firewalld documentation](https://firewalld.org/documentation/)
- [Ubuntu ufw documentation](https://help.ubuntu.com/community/UFW)
- [GitHub: Accessing public SSH keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/about-ssh)

## Repo Structure

```
autoinstallscripts/
├── README.md
└── Linux/
    ├── auto_install_upgrade_server_fedora.sh
    └── auto_install_upgrade_server_debian.sh
```

## License

Use these however you like. No warranty — review before running, especially anything that touches SSH config.
