# autoinstallscripts

Bootstrap and configuration scripts for fresh VMs on Proxmox — Linux and Windows.

## Repo Structure

```
autoinstallscripts/
├── Linux/
│   ├── auto_install_upgrade_server_debian.sh   ← Debian 12+ / Ubuntu 22.04+
│   ├── auto_install_upgrade_server_fedora.sh   ← Fedora (latest)
│   ├── Auto Updates/
│   │   ├── setup-unattended-upgrades.sh        ← automated setup script
│   │   └── Ubuntu-Unattended-Upgrades-Setup.md ← full configuration guide
│   ├── testing/                                ← dev copies, not for production use
│   └── README.md                               ← full Linux documentation
└── Windows/
    ├── autounattend(1).xml                     ← Windows unattended install config
    └── windowsAU.txt                           ← link to Schneegans generator
```

## Quick Start — Linux

### Debian / Ubuntu

```bash
curl -fsSL -o bootstrap.sh \
  https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_debian.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

### Fedora

```bash
curl -fsSL -o bootstrap.sh \
  https://raw.githubusercontent.com/migratingauto/autoinstallscripts/main/Linux/auto_install_upgrade_server_fedora.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

Each script updates packages, sets up the QEMU guest agent, configures SSH with keys from your GitHub profile, hardens SSH (disables password auth), and optionally installs Docker Engine. See [Linux/README.md](Linux/README.md) for prerequisites, the recommended safe workflow, and troubleshooting.

## Auto-Updates (Ubuntu)

After the bootstrap, run `setup-unattended-upgrades.sh` to configure security-only automatic updates:

```bash
sudo bash "Linux/Auto Updates/setup-unattended-upgrades.sh"
```

This sets up `unattended-upgrades` to automatically install security patches while leaving non-security updates and Docker packages for manual review. See [Linux/Auto Updates/Ubuntu-Unattended-Upgrades-Setup.md](Linux/Auto%20Updates/Ubuntu-Unattended-Upgrades-Setup.md) for the full configuration guide.

## Windows

`Windows/autounattend(1).xml` is an unattended install configuration for Windows Server. Place it on installation media so Windows Setup runs without interactive prompts. To generate a customized version, use the [Schneegans Windows Autounattend Generator](https://schneegans.de/windows/unattend-generator/) (link also saved in `Windows/windowsAU.txt`).

## License

Use these however you like. No warranty — review before running, especially anything that touches SSH config.
