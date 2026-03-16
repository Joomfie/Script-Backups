#!/bin/bash
# ============================================================
#  Bazzite App Installer Script
#  Package Manager: Flatpak (Flathub)
#  Generated for: Bazzite (Fedora-based Immutable Desktop)
# ============================================================

set -e

# ── Install tracking arrays ──────────────────────────────────
# FAILED_INSTALLS  : Flatpak apps that the script attempted but failed
# MANUAL_REQUIRED  : Items that ALWAYS need manual steps (Windows-only,
#                    not on Flathub, etc.) — populated inline as we go
FAILED_INSTALLS=()
MANUAL_REQUIRED=()

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; }

# ── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║        Bazzite App Installer  🚀                 ║"
echo "║        Flatpak-based installer script            ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Ensure Flatpak is available ─────────────────────
info "Checking Flatpak availability..."
if ! command -v flatpak &>/dev/null; then
    error "Flatpak is not installed. On Bazzite it should be pre-installed."
    error "Try: sudo rpm-ostree install flatpak && systemctl reboot"
    exit 1
fi
success "Flatpak found: $(flatpak --version)"

# ── Step 2: Add Flathub remote if missing ───────────────────
info "Ensuring Flathub remote is configured..."
if ! flatpak remote-list | grep -q "flathub"; then
    info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    success "Flathub added."
else
    success "Flathub already configured."
fi

echo ""

# ════════════════════════════════════════════════════════════
#  PRE-FLIGHT — SYSTEM DEPENDENCIES
#  These are host-level or Flatpak-level dependencies required
#  by apps that do NOT work fully on Fedora/Bazzite without them.
#  rpm-ostree is used sparingly and only where truly needed at
#  the system layer. Flatpak overrides and runtimes are preferred.
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Pre-flight: Dependencies & Runtimes ──────────────${RESET}"
echo ""

# ── 1. Bottles / Wine runtime prerequisites ─────────────────
# Bottles Flatpak is self-contained but requires these Flatpak
# extension runtimes to be present for full Wine/DXVK support.
info "Installing Flatpak runtimes required by Bottles / Wine apps..."
flatpak install -y flathub \
    org.freedesktop.Platform//23.08 \
    org.freedesktop.Platform.Compat.i386//23.08 \
    org.freedesktop.Platform.GL32.default//23.08 \
    org.freedesktop.Platform.VAAPI.Intel//23.08 \
    org.winehq.Wine.DLLs.dxvk//stable-23.08 2>&1 | grep -v "^$" || \
    warn "Some Wine/Bottles runtime extensions may have failed — Bottles will still work but may download them on first launch."
echo ""

# ── 2. Flatseal — Flatpak permissions manager ────────────────
# Required to grant Bottles and other sandboxed apps access to
# external drives, game directories, and devices.
info "Installing Flatseal (Flatpak permissions manager — needed for Bottles, GPU Screen Recorder, etc.)..."
flatpak install -y flathub com.github.tchx84.Flatseal 2>&1 && \
    success "Flatseal installed." || \
    warn "Flatseal install failed — you may need to manage Flatpak permissions manually."
echo ""

# ── 3. Wireshark: grant host network capture permissions ─────
# The Flatpak version of Wireshark is sandboxed and cannot
# capture network traffic by default. We pre-grant the override.
# The user must ALSO run: sudo usermod -aG wireshark $USER
# and log out/in for live capture to work.
info "Pre-configuring Flatpak permissions for Wireshark packet capture..."
flatpak override --user \
    --device=all \
    --share=network \
    org.wireshark.Wireshark 2>/dev/null && \
    success "Wireshark Flatpak permissions set." || \
    warn "Could not pre-set Wireshark permissions (it may not be installed yet — will apply after)."
echo ""

# ── 4. GPU Screen Recorder: device access ───────────────────
# Needs access to /dev/dri (GPU nodes) for hardware-accelerated
# capture. This override ensures it can see the GPU inside its sandbox.
info "Pre-configuring GPU access for GPU Screen Recorder..."
flatpak override --user \
    --device=dri \
    com.dec05eba.gpu_screen_recorder 2>/dev/null && \
    success "GPU Screen Recorder device permissions set." || \
    warn "Could not pre-set GPU Screen Recorder permissions (it may not be installed yet — will apply after)."
echo ""

# ── 5. Host-level system packages (rpm-ostree) ───────────────
# These are layered at the system level only where no Flatpak
# or container alternative exists. rpm-ostree changes require a
# REBOOT to take effect — the script will warn you at the end.
#
# Packages:
#   cabextract  — needed by Wine/Bottles to unpack .cab Windows installers
#   p7zip       — needed to extract multi-part archives used by some Windows apps
#   p7zip-plugins — additional codec support for 7z archives
#   usbutils    — provides lsusb; needed by Wireshark for USB capture devices
#   v4l-utils   — Video4Linux utilities; improves GPU Screen Recorder device detection
info "Checking and layering required system packages via rpm-ostree..."
info "(This will NOT reboot automatically — a reboot reminder appears at the end.)"

RPM_PACKAGES=(
    cabextract
    p7zip
    p7zip-plugins
    usbutils
    v4l-utils
)

PACKAGES_TO_INSTALL=()
for pkg in "${RPM_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
        PACKAGES_TO_INSTALL+=("$pkg")
    else
        success "  $pkg already installed — skipping."
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    info "Layering packages: ${PACKAGES_TO_INSTALL[*]}"
    if sudo rpm-ostree install --idempotent "${PACKAGES_TO_INSTALL[@]}"; then
        success "System packages queued for install: ${PACKAGES_TO_INSTALL[*]}"
        warn "A REBOOT IS REQUIRED for rpm-ostree changes to take effect."
        warn "Run: systemctl reboot   (or reboot after the script finishes)"
        RPM_OSTREE_PENDING=true
    else
        warn "rpm-ostree install had issues — some system-level dependencies may be missing."
        warn "You can retry manually: sudo rpm-ostree install ${PACKAGES_TO_INSTALL[*]}"
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════
#  END PRE-FLIGHT
# ════════════════════════════════════════════════════════════

# ── App installer function ───────────────────────────────────
install_flatpak() {
    local name="$1"
    local app_id="$2"

    echo -e "${CYAN}▸ Installing:${RESET} ${BOLD}${name}${RESET} (${app_id})"

    if flatpak list --app | grep -q "${app_id}"; then
        success "${name} is already installed — skipping."
    else
        if flatpak install -y flathub "${app_id}" 2>&1; then
            success "${name} installed successfully."
        else
            error "Failed to install ${name}. Check your internet connection or the App ID."
            FAILED_INSTALLS+=("${name}|${app_id}")
        fi
    fi
    echo ""
}

# ════════════════════════════════════════════════════════════
#  SECTION 1 — BROWSERS
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Browsers ─────────────────────────────────────────${RESET}"
echo ""

install_flatpak "Floorp Browser"   "one.ablaze.floorp"
install_flatpak "Waterfox"         "net.waterfox.waterfox"
install_flatpak "Google Chrome"    "com.google.Chrome"

# ════════════════════════════════════════════════════════════
#  SECTION 2 — GAMING
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Gaming ───────────────────────────────────────────${RESET}"
echo ""

install_flatpak "Steam"            "com.valvesoftware.Steam"

# Playnite (Windows-only) — handled via Bottles
warn "Playnite is Windows-only. Installing Bottles so you can run it via Wine."
install_flatpak "Bottles (Wine manager for Playnite & others)" "com.usebottles.bottles"
MANUAL_REQUIRED+=("PLAYNITE")

# Post-install: grant Bottles the filesystem and device permissions it
# needs to reach external drives, game directories, and /dev/dri.
info "Configuring Bottles Flatpak permissions (filesystem + GPU access)..."
flatpak override --user \
    --filesystem=host \
    --device=dri \
    --share=network \
    com.usebottles.bottles 2>/dev/null && \
    success "Bottles permissions configured." || \
    warn "Could not auto-configure Bottles permissions — open Flatseal and grant 'All user files' + GPU access manually."
echo ""
info "Tip: Use Flatseal (installed above) to review and adjust Bottles permissions at any time."
echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 3 — VPN
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── VPN ──────────────────────────────────────────────${RESET}"
echo ""

# NOTE: The Flatpak version of Surfshark does NOT include the Kill Switch feature.
# For Kill Switch support, use the Snap or .deb version instead.
warn "Surfshark Flatpak does NOT include the Kill Switch feature."
warn "If you need Kill Switch, install via Snap or .deb from surfshark.com/download/linux instead."
install_flatpak "Surfshark VPN"    "com.surfshark.Surfshark"
MANUAL_REQUIRED+=("SURFSHARK")

# ════════════════════════════════════════════════════════════
#  SECTION 4 — COMMUNICATION
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Communication ────────────────────────────────────${RESET}"
echo ""

install_flatpak "Discord"                               "com.discordapp.Discord"
install_flatpak "Vesktop (Privacy-friendly Discord)"    "dev.vencord.Vesktop"

# ════════════════════════════════════════════════════════════
#  SECTION 5 — MUSIC
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Music ────────────────────────────────────────────${RESET}"
echo ""

install_flatpak "Spotify"          "com.spotify.Client"

# ════════════════════════════════════════════════════════════
#  SECTION 6 — DEVELOPMENT
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Development ──────────────────────────────────────${RESET}"
echo ""

install_flatpak "VSCodium"         "com.vscodium.codium"
install_flatpak "Wireshark"        "org.wireshark.Wireshark"
# Wireshark live capture requires the current user to be in the 'wireshark' group.
# On Bazzite/Fedora the group may not exist (it's usually created by a native RPM install),
# so we create it if missing and add the current user.
info "Setting up wireshark group for live packet capture..."
if ! getent group wireshark &>/dev/null; then
    sudo groupadd wireshark && info "Created 'wireshark' group."
fi
sudo usermod -aG wireshark "$USER" 2>/dev/null && \
    success "Added $USER to 'wireshark' group. Log out and back in (or reboot) for this to take effect." || \
    warn "Could not add $USER to 'wireshark' group — run: sudo usermod -aG wireshark \$USER"
echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 7 — SECURITY & PRIVACY
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Security & Privacy ───────────────────────────────${RESET}"
echo ""

# VeraCrypt: Not available on Flathub. Must be installed manually.
# There are known issues mounting volumes on Bazzite/immutable distros.
warn "VeraCrypt is NOT on Flathub and has known volume-mounting issues on Bazzite."
echo -e "  ${BOLD}Steps to install VeraCrypt manually:${RESET}"
echo -e "  1. Visit:  ${CYAN}https://veracrypt.fr/en/Downloads.html${RESET}"
echo -e "  2. Download the ${BOLD}Linux Generic Installer (.tar.bz2)${RESET}"
echo -e "  3. Extract and run the GUI installer inside."
echo -e "  4. See known Bazzite issues at:"
echo -e "     ${CYAN}https://sourceforge.net/p/veracrypt/discussion/features/thread/42eb99f6b4/${RESET}"
echo ""
MANUAL_REQUIRED+=("VERACRYPT")

# ════════════════════════════════════════════════════════════
#  SECTION 8 — GAME LAUNCHERS & STORES
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Game Launchers & Stores ──────────────────────────${RESET}"
echo ""

install_flatpak "itch.io Launcher"  "io.itch.itch"

# CurseForge has no official Linux/Flatpak app.
# ATLauncher on Flathub supports both CurseForge AND Modrinth modpacks.
warn "CurseForge has no official Linux client. Installing ATLauncher (supports CurseForge + Modrinth)."
install_flatpak "ATLauncher (CurseForge + Modrinth)" "com.atlauncher.ATLauncher"

install_flatpak "Modrinth App"      "com.modrinth.ModrinthApp"

# Rockstar Games Launcher: Windows-only, no Linux version exists.
warn "Rockstar Games Launcher is Windows-only. Use Bottles (installed above) to run it."
echo -e "  1. Open Bottles → create a new 'Gaming' bottle."
echo -e "  2. Download launcher .exe from:"
echo -e "     ${CYAN}https://socialclub.rockstargames.com/rockstar-games-launcher${RESET}"
echo -e "  3. Install the .exe inside your Bottles environment."
echo ""
MANUAL_REQUIRED+=("ROCKSTAR")

# ════════════════════════════════════════════════════════════
#  SECTION 9 — MOD MANAGERS
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Mod Managers ─────────────────────────────────────${RESET}"
echo ""

install_flatpak "r2modman (Thunderstore Mod Manager)" "com.github.ebkr.r2modman"

# BG3 Mod Manager: Windows-only .NET app — run via Bottles
warn "BG3 Mod Manager is a Windows .NET app — no native Linux build exists."
echo -e "  Use Bottles (already installed) to run it:"
echo -e "  1. Download from: ${CYAN}https://github.com/LaughingLeader/BG3ModManager/releases${RESET}"
echo -e "  2. In Bottles, create a new bottle and install .NET 8 Desktop Runtime."
echo -e "  3. Run BG3ModManager.exe inside the bottle."
echo -e "  4. Linux tips: ${CYAN}https://github.com/LaughingLeader/BG3ModManager/issues/12${RESET}"
echo ""
MANUAL_REQUIRED+=("BG3MODMANAGER")

# Thunderstore App (official): Overwolf-based, Windows-only.
# r2modman (installed above) covers all Thunderstore games on Linux.
warn "The official Thunderstore desktop app is Overwolf-based (Windows-only)."
warn "r2modman (installed above) handles all Thunderstore games on Linux."
echo ""

# Vortex: Windows-only. Best Linux alternative is Limo (Flatpak) or Nexus Mods App.
warn "Vortex is Windows-only. Installing Limo as a Linux-native mod manager alternative."
echo -e "  For larger mod lists, the Nexus Mods App is in active development:"
echo -e "  ${CYAN}https://github.com/Nexus-Mods/NexusMods.App${RESET}"
install_flatpak "Limo (Linux Mod Manager)" "io.github.limo_app.limo"

# RedModManager (Cyberpunk 2077 REDmod): Windows-only, bundled with game via Steam.
warn "REDmod (Cyberpunk 2077) is Windows-only. On Linux via Proton, use r2modman for Cyberpunk mods."
echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 10 — HARDWARE MONITORING
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Hardware Monitoring ──────────────────────────────${RESET}"
echo ""

# Core Temp, HWiNFO64, OpenHardwareMonitor: All Windows-only.
# MangoHud is the Linux equivalent — in-game overlay showing CPU/GPU temps, FPS, etc.
warn "Core Temp, HWiNFO64, and OpenHardwareMonitor are all Windows-only."
echo -e "  Installing ${BOLD}MangoHud${RESET} (best Linux equivalent — in-game CPU/GPU/temp overlay)"
echo -e "  and ${BOLD}GOverlay${RESET} (graphical config tool for MangoHud)."
echo ""

# MangoHud Flatpak layer (for use with Flatpak Steam)
echo -e "${CYAN}▸ Installing:${RESET} ${BOLD}MangoHud Vulkan Layer${RESET} (org.freedesktop.Platform.VulkanLayer.MangoHud)"
flatpak install -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud 2>&1 && \
    success "MangoHud layer installed." || \
    warn "MangoHud layer install had issues — try: flatpak install flathub org.freedesktop.Platform.VulkanLayer.MangoHud"
echo ""

# Enable MangoHud globally for Flatpak Steam
echo -e "${CYAN}▸ Enabling MangoHud for Flatpak Steam...${RESET}"
flatpak override --user --env=MANGOHUD=1 com.valvesoftware.Steam 2>/dev/null && \
    success "MangoHud enabled for Steam." || \
    warn "Could not auto-enable MangoHud for Steam — add MANGOHUD=1 to each game's launch options manually."
echo ""

install_flatpak "GOverlay (MangoHud GUI configurator)" "page.codeberg.Heldek.GOverlay"

# ════════════════════════════════════════════════════════════
#  SECTION 11 — SCREENSHOT / SCREEN CAPTURE
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Screenshot & Screen Capture ──────────────────────${RESET}"
echo ""

# ShareX is Windows-only. Flameshot is the top-rated Linux equivalent.
warn "ShareX is Windows-only. Installing Flameshot — the best Linux screenshot tool equivalent."
install_flatpak "Flameshot (ShareX alternative)" "org.flameshot.Flameshot"

# ════════════════════════════════════════════════════════════
#  SECTION 12 — GAME CLIPPING
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Game Clipping ────────────────────────────────────${RESET}"
echo ""

# Medal.tv: Officially confirmed no Linux support.
# GPU Screen Recorder is the best Linux equivalent (GPU-accelerated, low overhead).
warn "Medal.tv has no Linux support (officially confirmed by Medal support team)."
echo -e "  Installing ${BOLD}GPU Screen Recorder${RESET} — GPU-accelerated recorder similar to Medal/ShadowPlay."
install_flatpak "GPU Screen Recorder (Medal.tv alternative)" "com.dec05eba.gpu_screen_recorder"

# ════════════════════════════════════════════════════════════
#  SECTION 13 — BORDERLESS GAMING
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Borderless Gaming ────────────────────────────────${RESET}"
echo ""

# Borderless Gaming (andrewmd5): Windows-only, confirmed no Linux support in GitHub issues.
# On Bazzite, Gamescope handles this natively and is already built in.
warn "Borderless Gaming is Windows-only (GitHub issue #482 confirms no Linux support)."
echo -e "  On Bazzite, ${BOLD}Gamescope${RESET} (already built in) handles borderless windowing."
echo -e "  Add this to any game's Steam launch options to force borderless fullscreen:"
echo -e "  ${YELLOW}gamescope -b -W 1920 -H 1080 -- %command%${RESET}"
echo -e "  (Replace 1920x1080 with your monitor's resolution.)"
echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 14 — CISCO PACKET TRACER (Manual)
# ════════════════════════════════════════════════════════════
echo -e "${BOLD}── Cisco Packet Tracer (Manual Install Required) ────${RESET}"
warn "Cisco Packet Tracer is NOT available on Flathub — must be downloaded manually."
echo -e "  ${BOLD}Steps:${RESET}"
echo -e "  1. Go to: ${CYAN}https://www.netacad.com/resources/lab-downloads${RESET}"
echo -e "  2. Sign in or create a free NetAcad account."
echo -e "  3. Download the ${BOLD}Linux (.rpm)${RESET} package."
echo -e "  4. Install it with:"
echo -e "     ${YELLOW}sudo rpm-ostree install ~/Downloads/CiscoPacketTracer*.rpm${RESET}"
echo -e "  5. Reboot: ${YELLOW}systemctl reboot${RESET}"
echo ""
MANUAL_REQUIRED+=("CISCO")

# ── Final Update ─────────────────────────────────────────────
echo -e "${BOLD}── Updating All Flatpak Apps ────────────────────────${RESET}"
info "Running flatpak update to ensure everything is current..."
flatpak update -y
success "All Flatpak apps are up to date."
echo ""

# ════════════════════════════════════════════════════════════
#  POST-INSTALL REPORT
#  Dynamically prints only what actually applies:
#    Section A — Flatpak installs that FAILED (with fix commands)
#    Section B — Items that ALWAYS need manual steps (with full guides)
#    Section C — Reboot notice if rpm-ostree changes are pending
# ════════════════════════════════════════════════════════════

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           POST-INSTALL REPORT                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Section A: Failed Flatpak installs ───────────────────────
if [ ${#FAILED_INSTALLS[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${RED}${BOLD}  ✗  SECTION A — FAILED INSTALLS  (action required)${RESET}"
    echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  The following apps did NOT install successfully."
    echo -e "  Each entry includes the exact command to retry manually."
    echo ""

    for entry in "${FAILED_INSTALLS[@]}"; do
        IFS='|' read -r fname fid <<< "$entry"
        echo -e "  ${RED}▸ ${BOLD}${fname}${RESET}  (${fid})"
        echo -e "    ${BOLD}Why it may have failed:${RESET}"
        echo -e "      • No internet connection at time of install"
        echo -e "      • Flathub was temporarily unavailable"
        echo -e "      • App ID may have changed on Flathub"
        echo -e "      • Disk space was insufficient"
        echo ""
        echo -e "    ${BOLD}How to fix:${RESET}"
        echo -e "    ${YELLOW}Step 1${RESET} — Confirm Flathub is reachable:"
        echo -e "      ${CYAN}flatpak remote-list${RESET}"
        echo -e "      (You should see 'flathub' in the list. If not:)"
        echo -e "      ${CYAN}flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Retry the install:"
        echo -e "      ${CYAN}flatpak install -y flathub ${fid}${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — If it still fails, search Flathub directly to confirm the App ID:"
        echo -e "      ${CYAN}flatpak search ${fname}${RESET}"
        echo -e "      or visit: ${CYAN}https://flathub.org${RESET}"
        echo ""
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
    done
else
    echo -e "${GREEN}${BOLD}  ✓  SECTION A — All Flatpak installs completed successfully.${RESET}"
    echo ""
fi

# ── Section B: Items always requiring manual steps ───────────
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}${BOLD}  !  SECTION B — MANUAL STEPS REQUIRED${RESET}"
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  The items below cannot be auto-installed. Follow each guide below."
echo ""

for item in "${MANUAL_REQUIRED[@]}"; do
    case "$item" in

    SURFSHARK)
        echo -e "  ${YELLOW}▸ ${BOLD}Surfshark VPN — Kill Switch not available in Flatpak${RESET}"
        echo ""
        echo -e "    ${BOLD}What was installed:${RESET}"
        echo -e "      The Flatpak version of Surfshark was installed, but it is"
        echo -e "      missing the Kill Switch feature due to Flatpak sandbox limits."
        echo ""
        echo -e "    ${BOLD}If you need Kill Switch, replace the Flatpak with the native .deb/.rpm:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Remove the Flatpak version:"
        echo -e "      ${CYAN}flatpak uninstall com.surfshark.Surfshark${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Download the native Linux installer from:"
        echo -e "      ${CYAN}https://surfshark.com/download/linux${RESET}"
        echo -e "      Choose the ${BOLD}.rpm${RESET} package for Fedora/Bazzite."
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Layer it via rpm-ostree:"
        echo -e "      ${CYAN}sudo rpm-ostree install ~/Downloads/surfshark-*.rpm${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — Reboot for the layer to activate:"
        echo -e "      ${CYAN}systemctl reboot${RESET}"
        echo ""
        echo -e "    ${BOLD}Note:${RESET} The Kill Switch will be available after this native install."
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    PLAYNITE)
        echo -e "  ${YELLOW}▸ ${BOLD}Playnite — Windows-only, run via Bottles${RESET}"
        echo ""
        echo -e "    ${BOLD}What was installed:${RESET}"
        echo -e "      Bottles (Wine manager) was installed as the host for Playnite."
        echo -e "      Playnite itself is a Windows .NET application with no Linux build."
        echo ""
        echo -e "    ${BOLD}How to set up Playnite inside Bottles:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Open Bottles from your app launcher."
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Click '${BOLD}+${RESET}' to create a new bottle."
        echo -e "      • Name: Playnite (or anything you like)"
        echo -e "      • Environment: ${BOLD}Application${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Inside the bottle, go to ${BOLD}Dependencies${RESET} and install:"
        echo -e "      • ${BOLD}dotnet48${RESET} or ${BOLD}dotnet6${RESET} (.NET runtime Playnite needs)"
        echo -e "      • ${BOLD}vcredist2019${RESET} (Visual C++ redistributable)"
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — Download the Playnite installer:"
        echo -e "      ${CYAN}https://playnite.link/download.html${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 5${RESET} — In Bottles, click ${BOLD}Run Executable${RESET} and select the"
        echo -e "      Playnite installer .exe. Follow the installer."
        echo ""
        echo -e "    ${YELLOW}Step 6${RESET} — After install, run Playnite.FullscreenApp.exe or"
        echo -e "      Playnite.DesktopApp.exe from the bottle's program list."
        echo ""
        echo -e "    ${BOLD}Tip:${RESET} Enable ${BOLD}DXVK${RESET} in the bottle's settings if Playnite's"
        echo -e "    UI renders incorrectly."
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    VERACRYPT)
        echo -e "  ${YELLOW}▸ ${BOLD}VeraCrypt — Not on Flathub, known issues on Bazzite${RESET}"
        echo ""
        echo -e "    ${BOLD}Why it can't be auto-installed:${RESET}"
        echo -e "      VeraCrypt is not available on Flathub. The generic Linux"
        echo -e "      installer works, but mounting encrypted volumes on immutable"
        echo -e "      distros like Bazzite has known issues due to the read-only"
        echo -e "      filesystem and FUSE restrictions."
        echo ""
        echo -e "    ${BOLD}Installation steps:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Download the Linux Generic Installer from:"
        echo -e "      ${CYAN}https://veracrypt.fr/en/Downloads.html${RESET}"
        echo -e "      Choose: ${BOLD}Linux > Generic Installer (.tar.bz2)${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Extract the archive:"
        echo -e "      ${CYAN}tar -xjf ~/Downloads/veracrypt-*-setup.tar.bz2 -C ~/Downloads/${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Run the GUI installer:"
        echo -e "      ${CYAN}~/Downloads/veracrypt-*-setup-gui-x64${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — For volume mounting issues on Bazzite, install fuse:"
        echo -e "      ${CYAN}sudo rpm-ostree install fuse fuse3${RESET}"
        echo -e "      Then reboot: ${CYAN}systemctl reboot${RESET}"
        echo ""
        echo -e "    ${BOLD}Known issue thread (volume mounting on immutable distros):${RESET}"
        echo -e "      ${CYAN}https://sourceforge.net/p/veracrypt/discussion/features/thread/42eb99f6b4/${RESET}"
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    ROCKSTAR)
        echo -e "  ${YELLOW}▸ ${BOLD}Rockstar Games Launcher — Windows-only, run via Bottles${RESET}"
        echo ""
        echo -e "    ${BOLD}Why it can't be auto-installed:${RESET}"
        echo -e "      Rockstar Games Launcher is Windows-only. There is no Linux"
        echo -e "      or Flatpak build. It must run inside a Wine/Bottles environment."
        echo ""
        echo -e "    ${BOLD}How to set it up in Bottles:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Open Bottles from your app launcher."
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Click '+' to create a new bottle."
        echo -e "      • Name: Rockstar (or anything you like)"
        echo -e "      • Environment: ${BOLD}Gaming${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Inside the bottle, go to ${BOLD}Dependencies${RESET} and install:"
        echo -e "      • ${BOLD}vcredist2019${RESET}"
        echo -e "      • ${BOLD}dotnet48${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — Download the Rockstar launcher installer (.exe) from:"
        echo -e "      ${CYAN}https://socialclub.rockstargames.com/rockstar-games-launcher${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 5${RESET} — In Bottles, click ${BOLD}Run Executable${RESET} and select the"
        echo -e "      Rockstar Games Launcher installer .exe."
        echo ""
        echo -e "    ${YELLOW}Step 6${RESET} — Enable ${BOLD}DXVK${RESET} and ${BOLD}VKD3D${RESET} in the bottle's settings"
        echo -e "      for best game compatibility."
        echo ""
        echo -e "    ${BOLD}Tip:${RESET} GTA V and RDR2 both work via Steam + Proton directly"
        echo -e "    without needing the Rockstar launcher at all."
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    BG3MODMANAGER)
        echo -e "  ${YELLOW}▸ ${BOLD}BG3 Mod Manager — Windows .NET app, run via Bottles${RESET}"
        echo ""
        echo -e "    ${BOLD}Why it can't be auto-installed:${RESET}"
        echo -e "      BG3 Mod Manager is a Windows .NET 8 application with no"
        echo -e "      native Linux build. It must run inside Bottles via Wine."
        echo ""
        echo -e "    ${BOLD}How to set it up in Bottles:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Open Bottles from your app launcher."
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Click '+' to create a new bottle."
        echo -e "      • Name: BG3ModManager"
        echo -e "      • Environment: ${BOLD}Application${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Inside the bottle, go to ${BOLD}Dependencies${RESET} and install:"
        echo -e "      • ${BOLD}dotnet8${RESET} (or dotnet8desktop — the Desktop Runtime is required)"
        echo -e "      • ${BOLD}vcredist2022${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — Download BG3ModManager from GitHub Releases:"
        echo -e "      ${CYAN}https://github.com/LaughingLeader/BG3ModManager/releases${RESET}"
        echo -e "      Get the ${BOLD}BG3ModManager.zip${RESET} (portable version recommended)."
        echo ""
        echo -e "    ${YELLOW}Step 5${RESET} — Extract the zip, then in Bottles click"
        echo -e "      ${BOLD}Run Executable${RESET} and select ${BOLD}BG3ModManager.exe${RESET}."
        echo ""
        echo -e "    ${YELLOW}Step 6${RESET} — Point BG3ModManager to your BG3 game data folder."
        echo -e "      If BG3 is installed via Steam Flatpak, the path is typically:"
        echo -e "      ${CYAN}~/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/Baldurs Gate 3${RESET}"
        echo ""
        echo -e "    ${BOLD}Known Linux issues & workarounds:${RESET}"
        echo -e "      ${CYAN}https://github.com/LaughingLeader/BG3ModManager/issues/12${RESET}"
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    CISCO)
        echo -e "  ${YELLOW}▸ ${BOLD}Cisco Packet Tracer — Not on Flathub, requires NetAcad account${RESET}"
        echo ""
        echo -e "    ${BOLD}Why it can't be auto-installed:${RESET}"
        echo -e "      Cisco Packet Tracer is proprietary and requires a free Cisco"
        echo -e "      NetAcad account to download. It is not on Flathub."
        echo ""
        echo -e "    ${BOLD}Installation steps:${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 1${RESET} — Create a free account (if you don't have one) at:"
        echo -e "      ${CYAN}https://www.netacad.com${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 2${RESET} — Log in and go to the downloads page:"
        echo -e "      ${CYAN}https://www.netacad.com/resources/lab-downloads${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 3${RESET} — Download the ${BOLD}Linux (.rpm)${RESET} package."
        echo ""
        echo -e "    ${YELLOW}Step 4${RESET} — Layer it with rpm-ostree:"
        echo -e "      ${CYAN}sudo rpm-ostree install ~/Downloads/CiscoPacketTracer*.rpm${RESET}"
        echo ""
        echo -e "    ${YELLOW}Step 5${RESET} — Reboot to activate the layer:"
        echo -e "      ${CYAN}systemctl reboot${RESET}"
        echo ""
        echo -e "    ${BOLD}Note:${RESET} After reboot, launch Packet Tracer from your app menu."
        echo -e "    You will be prompted to log in with your NetAcad account on first launch."
        echo -e "    ─────────────────────────────────────────────────────────"
        echo ""
        ;;

    esac
done

# ── Section C: Reboot notice ─────────────────────────────────
if [ "${RPM_OSTREE_PENDING:-false}" = true ]; then
    echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${RED}${BOLD}  ⚠   SECTION C — REBOOT REQUIRED${RESET}"
    echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  rpm-ostree layered packages (cabextract, p7zip, usbutils, v4l-utils)"
    echo -e "  have been queued but will ${BOLD}NOT be active until you reboot.${RESET}"
    echo ""
    echo -e "  ${BOLD}To reboot now:${RESET}"
    echo -e "    ${CYAN}systemctl reboot${RESET}"
    echo ""
    echo -e "  ${BOLD}After rebooting:${RESET}"
    echo -e "    • Log out and back in so Wireshark group membership takes effect."
    echo -e "    • Bottles, GPU Screen Recorder, and Wine features that depend on"
    echo -e "      cabextract/p7zip will now work correctly."
    echo ""
fi

echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Report complete. Good luck out there.${RESET}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
