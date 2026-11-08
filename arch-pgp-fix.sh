#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║           arch-pgp-fix.sh                                    ║
# ║   Arch Linux / LainOS PGP & Keyring Troubleshooter           ║
# ║   Works with both sudo and doas, or as root                  ║
# ║                                                               ║
# ║   Fixes:                                                      ║
# ║     - PGP keys that cannot be looked up remotely             ║
# ║     - Keyring permission errors                              ║
# ║     - Database lock issues                                   ║
# ║     - SigLevel for custom/unsigned repos                     ║
# ║     - Fakeroot errors                                        ║
# ║     - Wlogout PGP errors                                     ║
# ║                                                               ║
# ║   Usage: bash arch-pgp-fix.sh                                ║
# ╚═══════════════════════════════════════════════════════════════╝

set -e

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

ok()   { echo -e "${GRN}  ✔ $*${RST}"; }
info() { echo -e "${CYN}  → $*${RST}"; }
warn() { echo -e "${YLW}  ⚠ $*${RST}"; }
err()  { echo -e "${RED}  ✘ $*${RST}"; }
step() { echo -e "\n${BLD}${CYN}[$1]${RST}${BLD} $2${RST}"; }

# ── Banner ────────────────────────────────────────────────────────────
echo -e "${CYN}"
cat << 'EOF'
 █████╗ ██████╗  ██████╗██╗  ██╗      ██████╗  ██████╗ ██╗  ██╗
██╔══██╗██╔══██╗██╔════╝██║  ██║      ██╔══██╗██╔════╝ ╚██╗██╔╝
███████║██████╔╝██║     ███████║█████╗██████╔╝██║  ███╗ ╚███╔╝ 
██╔══██║██╔══██╗██║     ██╔══██║╚════╝██╔═══╝ ██║   ██║ ██╔██╗ 
██║  ██║██║  ██║╚██████╗██║  ██║      ██║     ╚██████╔╝██╔╝ ██╗
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝      ╚═╝      ╚═════╝ ╚═╝  ╚═╝
         Arch Linux PGP & Keyring Troubleshooter
EOF
echo -e "${RST}"

# ── Privilege Detection ───────────────────────────────────────────────
step "0/7" "Detecting privilege method..."

if [ "$(id -u)" -eq 0 ]; then
    PRIV=""
    info "Running as root — no privilege escalation needed."
elif command -v doas &>/dev/null; then
    PRIV="doas"
    info "Found: doas"
elif command -v sudo &>/dev/null; then
    PRIV="sudo"
    info "Found: sudo"
else
    err "Neither doas nor sudo found, and not running as root."
    err "Please run this script as root: su -c 'bash arch-pgp-fix.sh'"
    exit 1
fi

PACMAN_CONF="/etc/pacman.conf"

# ── FIX 1: Remove Database Lock ──────────────────────────────────────
step "1/7" "Checking for stale database lock..."

LOCKFILE="/var/lib/pacman/db.lck"
if [ -f "$LOCKFILE" ]; then
    warn "Stale lock file found. Removing..."
    $PRIV rm -f "$LOCKFILE"
    ok "Lock removed."
else
    ok "No lock file found."
fi

# ── FIX 2: Fix Keyring Permissions ───────────────────────────────────
step "2/7" "Fixing keyring file permissions..."

$PRIV chown -R root:root /usr/share/pacman/keyrings/ 2>/dev/null && \
$PRIV chmod 755 /usr/share/pacman/keyrings/ 2>/dev/null && \
ok "Keyring permissions fixed." || warn "Could not fix keyring permissions."

# ── FIX 3: Reinitialize Keyring ──────────────────────────────────────
step "3/7" "Reinitializing pacman keyring..."

$PRIV pacman-key --init && ok "Keyring initialized." || warn "pacman-key --init had issues."
$PRIV pacman-key --populate archlinux && ok "Archlinux keys populated." || warn "Could not populate archlinux keys."

# Populate distro-specific keyrings if present
for keyring in lainoslinux cynageos; do
    if pacman -Qq "${keyring}-keyring" &>/dev/null; then
        info "Found ${keyring}-keyring, populating..."
        $PRIV pacman-key --populate "$keyring" && ok "${keyring} keys populated."
    fi
done

# ── FIX 4: Patch SigLevel in pacman.conf ─────────────────────────────
step "4/7" "Patching SigLevel in pacman.conf..."

# Global SigLevel in [options]
if grep -q "^\[options\]" "$PACMAN_CONF"; then
    if ! awk '/^\[options\]/{f=1} f && /^SigLevel/{found=1; exit} f && /^\[/ && !/^\[options\]/{exit}' "$PACMAN_CONF" | grep -q .; then
        info "Adding global SigLevel = Never to [options]..."
        $PRIV sed -i '/^\[options\]/a SigLevel          = Never\nLocalFileSigLevel = Never' "$PACMAN_CONF"
        ok "Global SigLevel set."
    else
        # Make sure existing SigLevel is set to Never
        $PRIV sed -i 's/^SigLevel\s*=.*/SigLevel          = Never/' "$PACMAN_CONF"
        $PRIV sed -i 's/^LocalFileSigLevel\s*=.*/LocalFileSigLevel = Never/' "$PACMAN_CONF"
        ok "Global SigLevel updated."
    fi
fi

# Per-repo SigLevel for known unsigned repos
UNSIGNED_REPOS=("protocol_7_repo" "lainos_repo")
for repo in "${UNSIGNED_REPOS[@]}"; do
    if grep -q "^\[$repo\]" "$PACMAN_CONF"; then
        if ! awk "/^\[$repo\]/{f=1} f && /^SigLevel/{found=1; exit} f && /^\[/ && !/^\[$repo\]/{exit}" "$PACMAN_CONF" | grep -q .; then
            info "Adding SigLevel = Never to [$repo]..."
            $PRIV sed -i "/^\[$repo\]/a SigLevel = Never" "$PACMAN_CONF"
            ok "[$repo] patched."
        else
            ok "[$repo] already has SigLevel set."
        fi
    fi
done

# ── FIX 5: Fakeroot ──────────────────────────────────────────────────
step "5/7" "Checking fakeroot..."

$PRIV pacman -S --noconfirm fakeroot 2>/dev/null && ok "fakeroot OK." || warn "fakeroot install skipped."

# ── FIX 6: Wlogout PGP (optional) ────────────────────────────────────
step "6/7" "Wlogout PGP fix (optional)..."

echo -ne "${YLW}  → Fix wlogout PGP error? (y/n): ${RST}"
read -r fix_wlogout
if [[ "$fix_wlogout" =~ ^[Yy]$ ]]; then
    $PRIV pacman -S --noconfirm wlogout 2>/dev/null && ok "wlogout reinstalled." || warn "wlogout not in repos, skipping."
else
    info "Skipping wlogout fix."
fi

# ── FIX 7: Sync & Upgrade ────────────────────────────────────────────
step "7/7" "Syncing databases and upgrading..."

$PRIV pacman -Syu --noconfirm && ok "System upgraded successfully!" || {
    err "Upgrade failed. Trying with forced SigLevel override..."
    $PRIV pacman -Syu --noconfirm --config <(sed 's/^SigLevel\s*=.*/SigLevel = Never/' "$PACMAN_CONF")
}

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}"
echo -e "${GRN}${BLD}  ✔ All fixes applied!${RST}"
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}"
echo ""
echo -e "${CYN}Verify with:${RST}"
echo "  doas pacman -Syu    # should say 'nothing to do'"
echo "  tail -20 /var/log/pacman.log"
echo ""
echo -e "${YLW}If errors persist:${RST}"
echo "  1. Check /etc/pacman.conf for correct SigLevel"
echo "  2. Run: $PRIV pacman-key --refresh-keys"
echo "  3. Check your internet/DNS can reach keyservers"
echo ""
