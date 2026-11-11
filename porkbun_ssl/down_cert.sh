#!/bin/bash
set +x

# Path to configuration file (next to the script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Check if config exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Error: Configuration file $CONFIG_FILE not found!" >&2
    exit 1
fi

echo "=== Starting SSL certificate renewal ==="

# === Validate required variables ===
if [[ -z "$DOMAIN" || -z "$API_KEY" || -z "$SECRET_KEY" ]]; then
    echo "❌ Error: Required parameters (DOMAIN, API_KEY, SECRET_KEY) are missing in $CONFIG_FILE!" >&2
    exit 1
fi

CERT_PATH="${CERT_PATH:-/root/certs}"
CERT_NAME="${CERT_NAME:-cert.pem}"
KEY_NAME="${KEY_NAME:-privkey.key}"
DAYS_THRESHOLD="${DAYS_THRESHOLD:-7}"

# === API Settings ===
API_URL="https://api.porkbun.com/api/json/v3/ssl/retrieve/${DOMAIN}"

# === Package installation helper ===
install_package() {
    local pkg="$1"
    echo "⚙ $pkg not found, installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y && sudo apt-get install -y "$pkg"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "$pkg"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "$pkg"
    else
        echo "❌ Unable to detect package manager. Please install $pkg manually." >&2
        exit 1
    fi
}

for bin in curl jq openssl; do
    if ! command -v "$bin" &> /dev/null; then
        install_package "$bin"
    fi
done

# === Create target directory if needed ===
mkdir -p "$CERT_PATH"

FULLCHAIN="$CERT_PATH/$CERT_NAME"
KEYFILE="$CERT_PATH/$KEY_NAME"

if [[ -f "$FULLCHAIN" ]]; then
    echo "→ Checking current certificate expiration ($FULLCHAIN)..."
    expiry_date=$(openssl x509 -enddate -noout -in "$FULLCHAIN" 2>/dev/null | cut -d= -f2)
    expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null)
    now_ts=$(date +%s)

    if [[ -n "$expiry_ts" ]]; then
        days_left=$(( (expiry_ts - now_ts) / 86400 ))
        echo "   Certificate expires in $days_left days."

        if (( days_left > DAYS_THRESHOLD )); then
            echo "✅ Certificate is still valid (more than $DAYS_THRESHOLD days left). No renewal needed."
            exit 0
        fi
    else
        echo "⚠ Failed to determine certificate expiration date. Downloading new certificate..."
    fi
else
    echo "⚠ Certificate not found. Downloading new certificate..."
fi

# === API Request ===
echo "→ Requesting new certificates for $DOMAIN..."
response=$(curl -s "$API_URL" \
  -H "Content-Type: application/json" \
  -d "{
        \"apikey\": \"$API_KEY\",
        \"secretapikey\": \"$SECRET_KEY\"
      }")

if [[ -z "$response" ]]; then
    echo "❌ Error: Empty response from Porkbun API (check network connection)" >&2
    exit 1
fi

# === Check API response status ===
status=$(echo "$response" | jq -r '.status // empty')
if [[ "$status" != "SUCCESS" ]]; then
    echo "❌ Error: Request failed. Server response:" >&2
    echo "$response" >&2
    exit 1
fi

# === Extract certificates ===
certificatechain=$(echo "$response" | jq -r '.certificatechain // empty')
privatekey=$(echo "$response" | jq -r '.privatekey // empty')
if [ ${#certificatechain} -lt 100 ] || [ ${#privatekey} -lt 100 ]; then
    echo "❌ Error: Certificate or private key is suspiciously short — not saving" >&2
    exit 1
fi

echo "→ Saving new certificates to $CERT_PATH..."

printf "%s\n" "$certificatechain" > "$FULLCHAIN"
printf "%s\n" "$privatekey" > "$KEYFILE"

chmod 600 "$KEYFILE"
chmod 644 "$FULLCHAIN"

echo "✅ Certificates saved: $FULLCHAIN, $KEYFILE"

# === Execute post-update commands ===
if [[ ${#POST_COMMANDS[@]} -gt 0 ]]; then
    echo "→ Running post-update commands..."
    for cmd in "${POST_COMMANDS[@]}"; do
        [[ -z "$cmd" ]] && continue
        echo "  [RUN] $cmd"
        if eval "$cmd"; then
            echo "  [OK] Command executed successfully"
        else
            echo "❌ Error executing command: $cmd" >&2
            exit 1
        fi
    done
    echo "✅ All post-update commands executed successfully!"
else
    echo "ℹ POST_COMMANDS is empty or not set. Skipping service reload."
fi
