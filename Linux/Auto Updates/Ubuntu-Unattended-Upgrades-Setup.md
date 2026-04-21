# Ubuntu Server Automatic Security Updates Setup

## Overview

This guide configures **unattended-upgrades** on Ubuntu Server hosts to automatically install **security updates only**, with **no automatic reboots** and **Docker packages excluded** from auto-updates.

**Target hosts:** OnyxCinder, Hammerhead, Xwing, and any other Ubuntu VMs in the homelab.

**Configuration profile:**
- ✅ Security updates: auto-download and auto-install
- ❌ Regular (non-security) updates: manual only
- ❌ Automatic reboots: disabled
- ❌ Docker packages (docker-ce, docker-ce-cli, containerd.io, etc.): excluded from auto-updates
- ✅ Old dependencies auto-removed
- ✅ Download bandwidth limited (optional, prevents saturation during updates)

## Documentation References

- [Ubuntu Server Guide: Automatic Updates](https://ubuntu.com/server/docs/automatic-updates)
- [Debian Wiki: UnattendedUpgrades](https://wiki.debian.org/UnattendedUpgrades)
- [unattended-upgrades GitHub](https://github.com/mvo5/unattended-upgrades)
- [Ubuntu man page: unattended-upgrade](https://manpages.ubuntu.com/manpages/jammy/man8/unattended-upgrade.8.html)

---

## Part 1: Verify Installation

Ubuntu Server typically comes with `unattended-upgrades` pre-installed. Verify with:

```bash
dpkg -l | grep unattended-upgrades
```

If not installed, install it:

```bash
sudo apt update
sudo apt install unattended-upgrades apt-listchanges -y
```

**What these packages do:**
- `unattended-upgrades` — The core package that handles automatic updates
- `apt-listchanges` — Shows changelog entries for packages being upgraded (useful for logs)

---

## Part 2: Configure unattended-upgrades

### Step 2.1: Back up the original config

Always back up before editing:

```bash
sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.backup
```

### Step 2.2: Edit the main configuration file

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

### Step 2.3: Configure the allowed origins (security updates only)

Find the `Unattended-Upgrade::Allowed-Origins` block near the top. It should look like this when properly configured for **security updates only**:

```conf
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
//      "${distro_id}:${distro_codename}-updates";
//      "${distro_id}:${distro_codename}-proposed";
//      "${distro_id}:${distro_codename}-backports";
};
```

**Explanation:**
- `${distro_codename}-security` — Official Ubuntu security updates ✅
- `ESMApps-security` / `ESM-infra-security` — Extended Security Maintenance (free for up to 5 machines with Ubuntu Pro) ✅
- `-updates` — General non-security updates (commented out = disabled) ❌
- `-proposed` — Testing repository (should NEVER be enabled on production) ❌
- `-backports` — Backported packages from newer releases ❌

Lines starting with `//` are comments. Make sure `-updates`, `-proposed`, and `-backports` lines are commented out.

### Step 2.4: Configure the package blacklist (exclude Docker)

Find the `Unattended-Upgrade::Package-Blacklist` block and add Docker-related packages:

```conf
Unattended-Upgrade::Package-Blacklist {
    "docker-ce";
    "docker-ce-cli";
    "docker-ce-rootless-extras";
    "docker-buildx-plugin";
    "docker-compose-plugin";
    "containerd.io";
    // Add other packages you want to pin to manual updates below
};
```

**Why blacklist Docker?** Docker Engine updates can occasionally restart the Docker daemon, which briefly disrupts running containers. By blacklisting, you control exactly when Docker updates happen (typically during a planned maintenance window).

You can add regex patterns too. For example, to blacklist any package starting with `linux-`:

```conf
"linux-.*";
```

However, we'll leave kernel updates enabled since they're security-relevant — they just won't trigger a reboot automatically.

### Step 2.5: Configure reboot behavior (DISABLED)

Find these lines and make sure they're set as follows:

```conf
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

**To enable smart reboots in the future** (your Question 4):

When you decide you want automatic reboots (e.g., during a weekly maintenance window), change to:

```conf
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

This would reboot at 4 AM **only if a reboot is actually required** (indicated by the presence of `/var/run/reboot-required`). Updates that don't need a reboot won't trigger one.

**Alternative: use `needrestart` for smarter service-level restarts** (no full reboot needed):

```bash
sudo apt install needrestart -y
```

`needrestart` detects which specific services need restarting after a library update and restarts only those, avoiding full reboots in many cases. It's great for Docker hosts.

### Step 2.6: Configure auto-removal of unused dependencies

Find and set these:

```conf
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
```

This keeps `/boot` from filling up with old kernels and prevents orphan packages from accumulating.

### Step 2.7: Configure logging

Make sure these are set (they usually are by default):

```conf
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
```

Logs will be written to:
- `/var/log/unattended-upgrades/unattended-upgrades.log` (main log)
- `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` (package install output)
- `journalctl` (via syslog)

### Step 2.8: Optional — Bandwidth limit

If you want to prevent updates from saturating your connection (nice for the Plex/download-heavy OnyxCinder):

```conf
Acquire::http::Dl-Limit "5000";
```

This limits apt download speed to 5000 KB/s (~40 Mbit). Adjust or leave commented out to disable.

### Step 2.9: Save and exit

In nano: `Ctrl+O`, `Enter`, `Ctrl+X`.

---

## Part 3: Enable the Automatic Update Schedule

This is a separate config file that controls **when** unattended-upgrades actually runs.

### Step 3.1: Create/edit the periodic config

```bash
sudo nano /etc/apt/apt.conf.d/20auto-upgrades
```

### Step 3.2: Set the schedule

Paste in:

```conf
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
```

**Explanation:**
- `Update-Package-Lists "1"` — Run `apt update` every 1 day
- `Download-Upgradeable-Packages "1"` — Download updates every 1 day
- `Unattended-Upgrade "1"` — Install updates every 1 day
- `AutocleanInterval "7"` — Clean out old downloaded `.deb` files every 7 days

Setting a value to `"0"` disables that action. Setting to `"2"` runs it every 2 days, etc.

Save and exit.

---

## Part 4: Test the Configuration

### Step 4.1: Dry-run test

This simulates an unattended-upgrade run without actually changing anything:

```bash
sudo unattended-upgrade --dry-run --debug
```

**What to look for in the output:**
- Package origins being checked
- Any packages that would be upgraded
- Any packages that are on the blacklist (Docker should show here if Docker updates are available)
- No errors about config syntax

If you see errors like `Parse error`, there's a syntax issue in your config file. Re-check the braces `{}` and semicolons `;`.

### Step 4.2: Verify the config is valid

```bash
sudo unattended-upgrades --verbose
```

If this runs without a syntax error, you're good.

### Step 4.3: Check the timer status

Ubuntu uses systemd timers (not cron) to run unattended-upgrades:

```bash
systemctl list-timers | grep -E 'apt|unattended'
```

You should see:
- `apt-daily.timer` — Triggers package list updates and downloads
- `apt-daily-upgrade.timer` — Triggers the actual upgrade installation

Check the services are enabled:

```bash
systemctl status unattended-upgrades.service
systemctl status apt-daily.timer
systemctl status apt-daily-upgrade.timer
```

All should show `active (running)` or `active (waiting)`.

---

## Part 5: Verify It's Working (After First Run)

The default schedule runs:
- `apt-daily.timer` — around 6:00 AM and 6:00 PM (with random delay)
- `apt-daily-upgrade.timer` — around 6:00 AM (with random delay)

After the first run, check the logs:

```bash
# Main log
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades.log

# See all log files
ls -lh /var/log/unattended-upgrades/

# Check via journalctl
journalctl -u unattended-upgrades.service --since "24 hours ago"
```

**Check if a reboot is pending** (useful to know when to schedule manual reboots):

```bash
# If this file exists, a reboot is needed
ls /var/run/reboot-required 2>/dev/null && echo "REBOOT REQUIRED" || echo "No reboot needed"

# See which packages triggered the reboot-required flag
cat /var/run/reboot-required.pkgs 2>/dev/null
```

**Pro tip:** Add the reboot-required check to your `/etc/motd` or login banner so you see it when you SSH in. On Ubuntu this is typically already shown via `/etc/update-motd.d/98-reboot-required`.

---

## Part 6: Manual Trigger (For Testing or On-Demand)

To manually run unattended-upgrades right now:

```bash
sudo unattended-upgrade -d
```

The `-d` flag enables debug/verbose output so you can see what it's doing.

---

## Part 7: Repeating Across Multiple VMs

Since you want this on OnyxCinder, Hammerhead, Xwing, and other Ubuntu VMs, here are a few approaches:

### Option A: Manual Repeat (Simple)

Just SSH into each VM and run through this guide. Takes ~5 minutes per VM.

### Option B: Copy Config Files (Faster)

Once you've configured one host perfectly, copy the two config files to the others:

```bash
# On the source/reference host, grab the files:
scp /etc/apt/apt.conf.d/50unattended-upgrades user@targethost:/tmp/
scp /etc/apt/apt.conf.d/20auto-upgrades user@targethost:/tmp/

# On the target host:
sudo mv /tmp/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades
sudo mv /tmp/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
sudo chown root:root /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/20auto-upgrades
sudo chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/20auto-upgrades

# Verify:
sudo unattended-upgrade --dry-run --debug
```

### Option C: Bash Setup Script (Most Scalable)

I've included a setup script in the next section that you can run on any fresh Ubuntu VM to apply this config in one shot. This is the approach I'd recommend for your homelab since you're likely to add more VMs over time.

### Option D: Ansible (Future-proof, out of scope for now)

If your homelab keeps growing, you might want to look into Ansible for managing config across multiple hosts. That's a bigger topic but worth mentioning.

---

## Troubleshooting

### "Could not get lock /var/lib/dpkg/lock-frontend"

Something else is running apt. Wait, or:

```bash
ps aux | grep -E 'apt|dpkg|unattended'
```

### Updates aren't happening

Check the timer:

```bash
systemctl list-timers apt-daily-upgrade.timer
```

If `NEXT` is in the past or shows `n/a`, the timer may be disabled:

```bash
sudo systemctl enable --now apt-daily.timer
sudo systemctl enable --now apt-daily-upgrade.timer
```

### Config file syntax error

Always re-run the dry-run after editing:

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | head -20
```

Common mistakes:
- Missing semicolon `;` at end of a line inside `{}`
- Unmatched braces
- Quotes not closed

### Want to see what WOULD be upgraded right now

```bash
apt list --upgradable 2>/dev/null
```

---

## Quick Reference: Files Modified

| File | Purpose |
|------|---------|
| `/etc/apt/apt.conf.d/50unattended-upgrades` | Main config: what to update, what to exclude, reboot behavior |
| `/etc/apt/apt.conf.d/20auto-upgrades` | Schedule: how often to run |
| `/var/log/unattended-upgrades/` | Log directory |
| `/var/run/reboot-required` | Flag file indicating a reboot is pending |

---

## Future: Enabling Smart Reboots

When you're ready to let the system reboot itself (e.g., you've verified Docker containers all start correctly after a reboot), edit `/etc/apt/apt.conf.d/50unattended-upgrades`:

```conf
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

This reboots at 4 AM only when `/var/run/reboot-required` exists.

**Before enabling this, verify:**
1. All Docker containers have `restart: unless-stopped` or `restart: always` set in their compose files
2. Gluetun starts before qBittorrent (use `depends_on` in compose)
3. Plex, MariaDB, n8n, etc. all come up cleanly after a reboot (test with a manual reboot first!)

---

## Monitoring Ideas (Future)

Since you already have Prometheus + Grafana:

- **Node Exporter's textfile collector** can expose a metric for "reboot required" status — you could alert on it
- **Promtail + Loki** could ingest `/var/log/unattended-upgrades/` for centralized log searching
- **Uptime Kuma** could simply ping the host to alert you if a reboot happens unexpectedly

These are all optional enhancements for later.
