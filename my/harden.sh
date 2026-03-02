#!/usr/bin/env bash
# Security hardening for NanoClaw GCP e2-micro (Debian 12).
# Runs automatically on first boot via GCP startup-script metadata.
# Safe to re-run — all steps are idempotent.

set -euo pipefail
exec > /var/log/nanoclaw-harden.log 2>&1

echo "[$(date)] Starting hardening..."

# ── 1. System updates + common tools ─────────────────────────────────────────
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  ufw fail2ban unattended-upgrades apt-listchanges \
  git curl wget vim htop tmux \
  build-essential ca-certificates gnupg \
  unzip jq net-tools \
  python3 python3-pip python3-venv

# Node.js 22
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi

# Bun + uv + Claude Code (installed per-user for the default non-root user)
DEFAULT_USER=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$DEFAULT_USER" ]; then
  su -c 'bun --version &>/dev/null || curl -fsSL https://bun.sh/install | bash' "$DEFAULT_USER"
  su -c 'uv --version &>/dev/null || curl -fsSL https://astral.sh/uv/install.sh | sh' "$DEFAULT_USER"
  su -c 'claude --version &>/dev/null || npm install -g @anthropic-ai/claude-code' "$DEFAULT_USER"
fi

# ── 2. Automatic security updates ────────────────────────────────────────────
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Only apply security updates automatically (not all upgrades)
sed -i 's|//\s*"\${distro_id}:\${distro_codename}-updates";|// "${distro_id}:${distro_codename}-updates";|' \
  /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true

# ── 3. SSH hardening ─────────────────────────────────────────────────────────
SSHD_CONF=/etc/ssh/sshd_config

# Backup once
[ -f "${SSHD_CONF}.orig" ] || cp "$SSHD_CONF" "${SSHD_CONF}.orig"

apply_sshd() {
  local key="$1" val="$2"
  if grep -qE "^#?\s*${key}\s" "$SSHD_CONF"; then
    sed -i "s|^#\?\s*${key}\s.*|${key} ${val}|" "$SSHD_CONF"
  else
    echo "${key} ${val}" >> "$SSHD_CONF"
  fi
}

apply_sshd PermitRootLogin          no
apply_sshd PasswordAuthentication   no
apply_sshd ChallengeResponseAuthentication no
apply_sshd PubkeyAuthentication     yes
apply_sshd AuthorizedKeysFile       .ssh/authorized_keys
apply_sshd X11Forwarding            no
apply_sshd AllowTcpForwarding       no
apply_sshd MaxAuthTries             3
apply_sshd LoginGraceTime           30
apply_sshd ClientAliveInterval      300
apply_sshd ClientAliveCountMax      2

systemctl reload sshd

# ── 4. UFW firewall ───────────────────────────────────────────────────────────
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh          # port 22
ufw --force enable

# ── 5. fail2ban ───────────────────────────────────────────────────────────────
cat > /etc/fail2ban/jail.d/nanoclaw.conf <<'EOF'
[sshd]
enabled   = true
port      = ssh
maxretry  = 5
findtime  = 10m
bantime   = 1h
backend   = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# ── 6. Swap file (2 GB) ───────────────────────────────────────────────────────
# Critical for e2-micro — prevents OOM kills when Docker + Node.js are running.
if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Reduce swap aggressiveness — only use swap when RAM is nearly full
echo 'vm.swappiness=10' > /etc/sysctl.d/99-swap.conf
sysctl -w vm.swappiness=10 -q

# ── 7. Disable unused services ───────────────────────────────────────────────
for svc in bluetooth avahi-daemon cups; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

# ── 8. Kernel hardening (sysctl) ─────────────────────────────────────────────
cat > /etc/sysctl.d/99-nanoclaw.conf <<'EOF'
# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
# Block source-routed packets
net.ipv4.conf.all.accept_source_route = 0
# SYN flood protection
net.ipv4.tcp_syncookies = 1
# Ignore broadcast pings
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
sysctl --system -q

echo "[$(date)] Hardening complete."
