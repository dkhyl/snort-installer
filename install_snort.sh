#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Snort 3 Automated Installer for Linux (Cross‑Distribution)
# Author: dkhyl
# GitHub: https://github.com/dkhyl/snort-installer
# License: MIT
# ------------------------------------------------------------------------------
# Features:
#   - Detects Linux distribution and uses appropriate package manager
#   - Installs ALL required dependencies (including libfl-dev/FlexLexer.h)
#   - Removes existing/broken Snort installations
#   - Builds libdaq and Snort 3 from source
#   - Creates global symlink so 'snort' command works immediately
#   - Automatically configures shell aliases for DAQ path
#   - Verifies installation with comprehensive tests
#
# Usage: sudo ./install_snort.sh
# After installation, simply type: snort -V
# ------------------------------------------------------------------------------

set -euo pipefail

# ------------------------------ Configuration --------------------------------
SNORT_PREFIX="/usr/local/snort3"
DAQ_PREFIX="/usr/local/lib/daq_s3"
DAQ_CONF_FILE="/etc/ld.so.conf.d/libdaq3.conf"
LOG_FILE="/tmp/snort3_install_$(date +%Y%m%d_%H%M%S).log"
SNORT_SYMLINK="/usr/local/bin/snort"
ALIAS_CMD="alias snort='${SNORT_SYMLINK} --daq-dir ${DAQ_PREFIX}/lib/daq'"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------ Helper Functions -----------------------------
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

success() {
    log "${GREEN}✓ $*${NC}"
}

warning() {
    log "${YELLOW}⚠ $*${NC}"
}

error() {
    log "${RED}✗ $*${NC}"
    log "Check the log file for details: $LOG_FILE"
    exit 1
}

info() {
    log "${BLUE}→ $*${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

confirm() {
    read -r -p "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------ Distribution Detection -----------------------
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_VERSION="${VERSION_ID}"
    else
        error "Cannot detect Linux distribution. Missing /etc/os-release."
    fi

    case "$DISTRO_ID" in
        debian|ubuntu|linuxmint|pop|kali|parrot|elementary|zorin)
            PKG_MANAGER="apt"
            INSTALL_CMD="apt-get install -y --no-install-recommends"
            UPDATE_CMD="apt-get update -qq"
            ;;
        rhel|centos|fedora|rocky|almalinux|ol|amzn)
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf check-update || true"
            else
                PKG_MANAGER="yum"
                INSTALL_CMD="yum install -y"
                UPDATE_CMD="yum check-update || true"
            fi
            ;;
        arch|manjaro|endeavouros)
            PKG_MANAGER="pacman"
            INSTALL_CMD="pacman -S --noconfirm --needed"
            UPDATE_CMD="pacman -Sy"
            ;;
        opensuse*|suse)
            PKG_MANAGER="zypper"
            INSTALL_CMD="zypper install -y"
            UPDATE_CMD="zypper refresh"
            ;;
        *)
            error "Unsupported distribution: $DISTRO_ID"
            ;;
    esac
    log "Detected distribution: $DISTRO_ID ($PKG_MANAGER)"
}

# ------------------------------ Package Name Mapping -------------------------
map_package_names() {
    case "$PKG_MANAGER" in
        apt)
            PKGS_BUILD="build-essential cmake git pkg-config flex bison autoconf automake libtool"
            PKGS_LIBS="libpcap-dev libpcre3-dev libpcre2-dev libdumbnet-dev zlib1g-dev liblzma-dev libssl-dev libhwloc-dev luajit libluajit-5.1-dev libunwind-dev libsafec-dev libfl-dev"
            PKGS_OPT="asciidoc dblatex source-highlight w3m uuid-dev libhyperscan-dev flatbuffers-compiler-dev libflatbuffers-dev"
            ;;
        dnf|yum)
            PKGS_BUILD="gcc gcc-c++ make cmake git pkgconfig flex bison autoconf automake libtool flex-devel"
            PKGS_LIBS="libpcap-devel pcre-devel pcre2-devel libdnet-devel zlib-devel xz-devel openssl-devel hwloc-devel luajit luajit-devel libunwind-devel libsafec-devel"
            PKGS_OPT="asciidoc dblatex source-highlight w3m uuid-devel hyperscan-devel flatbuffers-devel"
            ;;
        pacman)
            PKGS_BUILD="base-devel cmake git pkg-config flex bison autoconf automake libtool"
            PKGS_LIBS="libpcap pcre pcre2 libdnet zlib xz openssl hwloc luajit libunwind safec flex"
            PKGS_OPT="asciidoc dblatex source-highlight w3m util-linux hyperscan flatbuffers"
            ;;
        zypper)
            PKGS_BUILD="gcc gcc-c++ make cmake git pkg-config flex bison autoconf automake libtool flex-devel"
            PKGS_LIBS="libpcap-devel pcre-devel pcre2-devel libdnet-devel zlib-devel xz-devel libopenssl-devel hwloc-devel luajit luajit-devel libunwind-devel libsafec-devel"
            PKGS_OPT="asciidoc dblatex source-highlight w3m uuid-devel hyperscan-devel flatbuffers-devel"
            ;;
    esac
}

# ------------------------------ Ensure Memory --------------------------------
ensure_memory() {
    local mem_available=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    if [[ $mem_available -lt 2000000 && $mem_available -ne 0 ]]; then
        warning "Available memory is low (${mem_available} KB). Adding 2GB temporary swap file."
        if [[ ! -f /swapfile_snort_build ]]; then
            fallocate -l 2G /swapfile_snort_build 2>/dev/null || dd if=/dev/zero of=/swapfile_snort_build bs=1M count=2048 2>/dev/null
            chmod 600 /swapfile_snort_build
            mkswap /swapfile_snort_build >/dev/null 2>&1
            swapon /swapfile_snort_build >/dev/null 2>&1
            success "Temporary swap added."
        fi
    fi
}

# ------------------------------ Cleanup Existing Snort -----------------------
clean_existing_snort() {
    log "Checking for existing Snort installations..."

    # Remove system packages if any
    if command -v dpkg &>/dev/null && dpkg -l 2>/dev/null | grep -q "snort"; then
        warning "Found Snort package installed via package manager."
        if confirm "Remove Snort packages? (This will also remove configuration files)"; then
            log "Removing Snort packages..."
            apt-get remove --purge -y snort* >> "$LOG_FILE" 2>&1 || true
            apt-get autoremove -y >> "$LOG_FILE" 2>&1 || true
            success "Snort packages removed."
        else
            error "Aborted by user."
        fi
    elif command -v rpm &>/dev/null && rpm -qa 2>/dev/null | grep -q "snort"; then
        warning "Found Snort RPM package installed."
        if confirm "Remove Snort packages?"; then
            log "Removing Snort packages..."
            rpm -e snort >> "$LOG_FILE" 2>&1 || true
            success "Snort packages removed."
        else
            error "Aborted by user."
        fi
    elif command -v pacman &>/dev/null && pacman -Q snort &>/dev/null; then
        warning "Found Snort installed via pacman."
        if confirm "Remove Snort?"; then
            pacman -Rsn --noconfirm snort >> "$LOG_FILE" 2>&1 || true
            success "Snort removed."
        else
            error "Aborted by user."
        fi
    fi

    # Check for manual installations
    local prefixes=("/usr/local" "/opt/snort" "/usr/local/snort3")
    for prefix in "${prefixes[@]}"; do
        if [[ -f "${prefix}/bin/snort" ]]; then
            warning "Found existing Snort binary at ${prefix}/bin/snort"
            if confirm "Remove this installation?"; then
                log "Removing ${prefix}/bin/snort and related files..."
                rm -rf "${prefix}/bin/snort"* "${prefix}/lib/snort"* "${prefix}/include/snort"* \
                       "${prefix}/etc/snort"* "${prefix}/share/snort"* 2>/dev/null || true
                success "Removed manual installation from $prefix"
            else
                error "Aborted by user."
            fi
        fi
    done

    # Remove old symlink if exists
    if [[ -L "$SNORT_SYMLINK" ]] || [[ -f "$SNORT_SYMLINK" ]]; then
        warning "Removing old snort symlink..."
        rm -f "$SNORT_SYMLINK"
    fi

    # Clean up old libdaq config
    if [[ -f "$DAQ_CONF_FILE" ]]; then
        rm -f "$DAQ_CONF_FILE"
        ldconfig || true
    fi

    success "Cleanup completed."
}

# ------------------------------ Install Dependencies -------------------------
install_dependencies() {
    log "Installing required packages for $DISTRO_ID..."
    $UPDATE_CMD >> "$LOG_FILE" 2>&1 || warning "Update command returned non-zero, continuing."

    map_package_names

    info "Installing build tools..."
    $INSTALL_CMD $PKGS_BUILD >> "$LOG_FILE" 2>&1 || error "Failed to install build tools."

    info "Installing required libraries..."
    $INSTALL_CMD $PKGS_LIBS >> "$LOG_FILE" 2>&1 || error "Failed to install required libraries."

    info "Installing optional packages (failures ignored)..."
    $INSTALL_CMD $PKGS_OPT >> "$LOG_FILE" 2>&1 || warning "Some optional packages could not be installed."

    success "Dependencies installed."
}

# ------------------------------ Build and Install libdaq ---------------------
install_libdaq() {
    log "Building libdaq (Snort 3 DAQ)..."

    if [[ -d "libdaq" ]]; then
        warning "libdaq directory exists, pulling latest changes..."
        cd libdaq
        git pull >> "$LOG_FILE" 2>&1 || warning "Could not update libdaq repository."
        cd ..
    else
        git clone --depth 1 https://github.com/snort3/libdaq.git >> "$LOG_FILE" 2>&1 \
            || error "Failed to clone libdaq."
    fi

    cd libdaq

    ./bootstrap >> "$LOG_FILE" 2>&1 || error "libdaq bootstrap failed."
    ./configure --prefix="$DAQ_PREFIX" >> "$LOG_FILE" 2>&1 \
        || error "libdaq configure failed."

    make -j"$(nproc)" >> "$LOG_FILE" 2>&1 || error "libdaq build failed."
    make install >> "$LOG_FILE" 2>&1 || error "libdaq install failed."

    cd ..

    echo "$DAQ_PREFIX/lib/" > "$DAQ_CONF_FILE"
    ldconfig

    success "libdaq installed to $DAQ_PREFIX"
}

# ------------------------------ Build and Install Snort 3 --------------------
install_snort3() {
    log "Building Snort 3..."

    if [[ -d "snort3" ]]; then
        warning "snort3 directory exists, pulling latest changes..."
        cd snort3
        git pull >> "$LOG_FILE" 2>&1 || warning "Could not update snort3 repository."
        cd ..
    else
        git clone --depth 1 https://github.com/snort3/snort3.git >> "$LOG_FILE" 2>&1 \
            || error "Failed to clone snort3."
    fi

    cd snort3

    # Unset any hardened flags that might break the build
    unset CFLAGS CXXFLAGS LDFLAGS

    ./configure_cmake.sh \
        --prefix="$SNORT_PREFIX" \
        --with-daq-includes="$DAQ_PREFIX/include/" \
        --with-daq-libraries="$DAQ_PREFIX/lib/" \
        >> "$LOG_FILE" 2>&1 || error "Snort CMake configuration failed."

    cd build
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1 || error "Snort build failed."
    make install >> "$LOG_FILE" 2>&1 || error "Snort install failed."

    cd ../..

    success "Snort 3 installed to $SNORT_PREFIX"
}

# ------------------------------ Create Global Symlink ------------------------
create_symlink() {
    log "Creating global symlink for snort command..."
    ln -sf "${SNORT_PREFIX}/bin/snort" "$SNORT_SYMLINK"
    success "Symlink created: $SNORT_SYMLINK -> ${SNORT_PREFIX}/bin/snort"
}

# ------------------------------ Setup Shell Integration ----------------------
setup_shell_integration() {
    log "Setting up shell integration..."

    # Get the original user (the one who ran sudo)
    local real_user="${SUDO_USER:-$USER}"
    local user_home=$(eval echo "~$real_user")

    # Add alias to shell config files
    local shell_configs=()
    [[ -f "$user_home/.bashrc" ]] && shell_configs+=("$user_home/.bashrc")
    [[ -f "$user_home/.zshrc" ]] && shell_configs+=("$user_home/.zshrc")

    for config in "${shell_configs[@]}"; do
        # Remove any existing snort alias
        sed -i '/alias snort=/d' "$config" 2>/dev/null || true
        # Add the new alias
        echo "$ALIAS_CMD" >> "$config"
        success "Added alias to $config"
    done

    # Ensure /usr/local/bin is in PATH (it usually is, but just in case)
    if ! echo "$PATH" | grep -q "/usr/local/bin"; then
        warning "Note: /usr/local/bin is not in your PATH. You may need to add it."
    fi
}

# ------------------------------ Post-Install Verification --------------------
verify_installation() {
    log "Verifying installation..."

    # Check binary exists
    if [[ ! -x "${SNORT_PREFIX}/bin/snort" ]]; then
        error "Snort binary not found at expected location."
    fi

    # Test version output using symlink
    info "Testing: snort -V"
    if ! "$SNORT_SYMLINK" -V >> "$LOG_FILE" 2>&1; then
        error "Snort -V failed. See log for details."
    fi
    success "Snort version check passed"

    # Test DAQ listing
    info "Testing: snort --daq-list"
    if ! "$SNORT_SYMLINK" --daq-dir "${DAQ_PREFIX}/lib/daq" --daq-list >> "$LOG_FILE" 2>&1; then
        warning "Snort could not list DAQ modules. You may need to use --daq-dir."
    else
        success "DAQ modules detected"
    fi

    # Show installed version
    local snort_version=$("$SNORT_SYMLINK" -V 2>&1 | head -3)
    info "Installed:\n$snort_version"
}

# ------------------------------ Final Instructions ---------------------------
print_summary() {
    local real_user="${SUDO_USER:-$USER}"
    
    echo ""
    echo "======================================================================"
    echo -e "${GREEN}🎉 Snort 3 Installation Complete!${NC}"
    echo "======================================================================"
    echo ""
    echo -e "${BLUE}Quick Start:${NC}"
    echo "  Just type: ${GREEN}snort -V${NC}"
    echo ""
    echo -e "${BLUE}Installation Details:${NC}"
    echo "  Binary:      $SNORT_SYMLINK -> ${SNORT_PREFIX}/bin/snort"
    echo "  DAQ modules: ${DAQ_PREFIX}/lib/daq/"
    echo "  Config dir:  ${SNORT_PREFIX}/etc/snort/"
    echo "  Log file:    $LOG_FILE"
    echo ""
    echo -e "${BLUE}Common Commands:${NC}"
    echo "  snort -V                     # Show version"
    echo "  snort --daq-list             # List packet acquisition modules"
    echo "  sudo snort -i eth0 -v        # Sniff packets (replace eth0)"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
    echo "  2. Create a config file: ${SNORT_PREFIX}/etc/snort/snort.lua"
    echo "  3. Download rules: https://www.snort.org/downloads"
    echo ""
    echo -e "${YELLOW}Note:${NC} The alias 'snort' automatically includes the correct DAQ path."
    echo "======================================================================"
}

# ------------------------------ Main Execution -------------------------------
main() {
    log "Starting Snort 3 automated installation script."
    check_root
    detect_distro

    # Create a working directory
    WORK_DIR="/tmp/snort3_build_$$"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    info "Working directory: $WORK_DIR"

    # Perform installation steps
    ensure_memory
    clean_existing_snort
    install_dependencies
    install_libdaq
    install_snort3
    create_symlink
    setup_shell_integration
    verify_installation

    # Clean up working directory
    cd /
    rm -rf "$WORK_DIR"
    success "Build directory cleaned up."

    # Remove temporary swap if we created it
    if [[ -f /swapfile_snort_build ]]; then
        swapoff /swapfile_snort_build 2>/dev/null || true
        rm -f /swapfile_snort_build
        success "Temporary swap removed."
    fi

    print_summary
    log "Script finished successfully."
}

# ------------------------------------------------------------------------------
main "$@"
