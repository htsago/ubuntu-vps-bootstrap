# Ubuntu VPS bootstrap hardening

Idempotent Bash script for first-time setup of Ubuntu or Debian cloud servers: sudo user, SSH key-only auth, Fail2ban, and conservative network sysctl values. Intended for interactive use on a new VPS where you already log in as root with an SSH key.

## Requirements

- Ubuntu or Debian
- Run as `root`
- At least one public key in `/root/.ssh/authorized_keys` before execution (the script exits otherwise)

## Quick start

**Recommended (inspect, then run):**

```bash
curl -fsSL https://raw.githubusercontent.com/htsago/ubuntu-vps-bootstrap/main/scripts/vps-harden-ubuntu.sh -o vps-harden-ubuntu.sh
less vps-harden-ubuntu.sh
sudo bash vps-harden-ubuntu.sh
```

**One-liner (only if you trust the source):**

```bash
curl -fsSL https://raw.githubusercontent.com/htsago/ubuntu-vps-bootstrap/main/scripts/vps-harden-ubuntu.sh | sudo bash
```

Replace `htsago/ubuntu-vps-bootstrap` and `main` if you use your own fork or branch.

## What the script does

| Area | Action |
|------|--------|
| Packages | `apt-get update`, installs OpenSSH client/server, `ca-certificates`, `curl`; optionally Fail2ban |
| Admin user | Creates `vpsadmin` (configurable), adds to `sudo`, copies root `authorized_keys` |
| Credentials | Random sudo password stored in `/root/<user>-credentials.txt` (mode `600`) when the user is new or that file is missing |
| SSH | Writes `/etc/ssh/sshd_config.d/00-vps-harden.conf` so it is parsed before `50-cloud-init.conf` on Ubuntu; disables password authentication; root may only use keys (`prohibit-password`) |
| Kernel | Writes `/etc/sysctl.d/99-network-hardening.conf` (does not change `ip_forward`) |
| Notes | `/root/access-notes.txt` summarizes access and recovery |

## Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `ADMIN_USER` | `vpsadmin` | Unix account with sudo |
| `SKIP_FAIL2BAN` | unset | Set to `1` to skip installing Fail2ban |
| `FORCE_SYNC_KEYS` | unset | Set to `1` to overwrite `~ADMIN_USER/.ssh/authorized_keys` from root |

Example:

```bash
sudo ADMIN_USER=deploy FORCE_SYNC_KEYS=1 bash vps-harden-ubuntu.sh
```

## Safety checklist

1. Ensure your SSH key works for `root` on this host.
2. Keep your current session open.
3. Run the script.
4. Open a **second** terminal and test: `ssh vpsadmin@<server-ip>` (or your `ADMIN_USER`).
5. Only then end the original session.

If something goes wrong, use your provider out-of-band console, adjust `/etc/ssh/sshd_config.d/`, and reload `ssh` / `sshd`.

## Limitations

- This is baseline hardening, not a full compliance profile (e.g. CIS). Review firewall rules, exposed application ports, backups, and updates for your workload.
- Running arbitrary remote scripts as root is a supply-chain risk; prefer downloading the file, reading it, then executing locally.

## License

MIT
