#!/usr/bin/env bash
# Bootstrap hardening for a fresh Ubuntu/Debian VPS (run as root).
#
# Remote install (replace USER/REPO/BRANCH as needed):
#   curl -fsSL https://raw.githubusercontent.com/USER/REPO/BRANCH/scripts/vps-harden-ubuntu.sh | sudo bash
#
# Local:
#   sudo bash scripts/vps-harden-ubuntu.sh
#
# Optional environment variables:
#   ADMIN_USER=vpsadmin       default sudo-capable user
#   SKIP_FAIL2BAN=1          skip fail2ban install
#   FORCE_SYNC_KEYS=1         overwrite ~ADMIN_USER/.ssh/authorized_keys from root

set -euo pipefail

ADMIN_USER="${ADMIN_USER:-vpsadmin}"
SSH_DROPIN="/etc/ssh/sshd_config.d/00-vps-harden.conf"
SYSCTL_FILE="/etc/sysctl.d/99-network-hardening.conf"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root (sudo -i or root shell)."

[[ -f /etc/os-release ]] || die "Missing /etc/os-release."
# shellcheck source=/dev/null
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "This script targets Ubuntu/Debian (ID=$ID)." ;;
esac

if [[ ! -s /root/.ssh/authorized_keys ]]; then
  die "No /root/.ssh/authorized_keys with keys. Add an SSH public key for root first, otherwise you will lock yourself out when SSH password login is disabled."
fi

echo "==> APT update & packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends openssh-server openssh-client ca-certificates curl

if [[ "${SKIP_FAIL2BAN:-0}" != "1" ]]; then
  apt-get install -y --no-install-recommends fail2ban
  systemctl enable --now fail2ban 2>/dev/null || true
fi

echo "==> Admin user: ${ADMIN_USER}"
if ! id "${ADMIN_USER}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${ADMIN_USER}"
  usermod -aG sudo "${ADMIN_USER}"
  NEW_USER=1
else
  NEW_USER=0
fi

install -d -m 700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
AK="/home/${ADMIN_USER}/.ssh/authorized_keys"
if [[ ! -s "${AK}" ]] || [[ "${FORCE_SYNC_KEYS:-0}" == "1" ]]; then
  cp -a /root/.ssh/authorized_keys "${AK}"
  chown "${ADMIN_USER}:${ADMIN_USER}" "${AK}"
  chmod 600 "${AK}"
  echo "    synced authorized_keys from root -> ${ADMIN_USER}"
else
  echo "    kept existing ${AK} (set FORCE_SYNC_KEYS=1 to replace)"
fi

CREDS="/root/${ADMIN_USER}-credentials.txt"
if [[ "${NEW_USER}" -eq 1 ]] || [[ ! -f "${CREDS}" ]]; then
  PW="$(openssl rand -base64 24 | tr -d '=/+')"
  printf '%s:%s\n' "${ADMIN_USER}" "${PW}" | chpasswd
  umask 077
  {
    echo "SSH user: ${ADMIN_USER} (same authorized_keys as root unless you changed them)"
    echo "Sudo password (change with: passwd):"
    echo "${PW}"
  } > "${CREDS}"
  chmod 600 "${CREDS}"
  echo "    sudo password written to ${CREDS} (root-readable only)"
elif [[ "${NEW_USER}" -eq 0 ]]; then
  echo "    existing user; ${CREDS} left unchanged (remove file to regenerate password on next run)"
fi

echo "==> SSH hardening (${SSH_DROPIN})"
# Parsed before 50-cloud-init.conf so OpenSSH "first token wins" keeps key-only auth.
cat >"${SSH_DROPIN}" <<'EOF'
# Early drop-in (00-*) - wins over 50-cloud-init.conf (PasswordAuthentication)
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 4
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
chmod 644 "${SSH_DROPIN}"

if sshd -t; then
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || die "sshd -t ok but reload failed"
  echo "    sshd reloaded"
else
  die "sshd -t failed - fix config manually"
fi

echo "==> Sysctl (${SYSCTL_FILE})"
cat >"${SYSCTL_FILE}" <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
fs.suid_dumpable = 0
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p "${SYSCTL_FILE}" || true

umask 077
cat >/root/access-notes.txt <<EOF
SSH:
- Password login is disabled; use your SSH key for root and ${ADMIN_USER}.
- Root SSH: key only (PermitRootLogin prohibit-password).
- Sudo for ${ADMIN_USER}: initial password in ${CREDS} (change with passwd).

Locked out? Use your provider serial/console, fix /etc/ssh/sshd_config.d/, then: systemctl reload ssh
EOF
chmod 600 /root/access-notes.txt

echo ""
echo "Done. Verify in a NEW terminal before closing this session:"
echo "  ssh ${ADMIN_USER}@$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "Sudo password: cat ${CREDS}"
echo "Summary: cat /root/access-notes.txt"
