#!/bin/bash

# --- Stop script if any error occurs ---
set -e

# --- 1. Check environment variables ---
# These variables must be set in the Xcode Cloud Environment Variables settings.
if [ -z "$GITHUB_APP_PRIVATE_KEY" ] || [ -z "$GITHUB_APP_CLIENT_ID" ] || [ -z "$GITHUB_APP_INSTALLATION_ID" ]; then
    echo "Error: Missing required environment variables (GITHUB_APP_PRIVATE_KEY, GITHUB_APP_CLIENT_ID, or GITHUB_APP_INSTALLATION_ID)."
    exit 1
fi

# --- 2. Define JWT generation function ---
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Create a temporary file for the private key
pem_file="$(mktemp)"
trap 'rm -f "$pem_file"' EXIT

# Decode the Base64-encoded private key and save it to the temporary file
echo "$GITHUB_APP_PRIVATE_KEY" | base64 -d > "$pem_file"

# Set expiration times (iat: issued at, exp: expires at)
now=$(date -u +%s)
iat=$((now - 60))
exp=$((now + 540))

header='{"alg":"RS256","typ":"JWT"}'
payload=$(cat <<JSON
{"iat":${iat},"exp":${exp},"iss":"${GITHUB_APP_CLIENT_ID}"}
JSON
)

h_b64=$(printf %s "$header" | b64url)
p_b64=$(printf %s "$payload" | b64url)
sig_b64=$(printf '%s.%s' "$h_b64" "$p_b64" | openssl dgst -binary -sha256 -sign "$pem_file" | b64url)
JWT="${h_b64}.${p_b64}.${sig_b64}"

# --- 3. Fetch Access Token from GitHub API ---
resp_body=$(curl -sS -X POST \
    -H "Authorization: Bearer ${JWT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens")

GH_TOKEN=$(printf %s "$resp_body" | jq -r '.token // empty')

if [ -z "$GH_TOKEN" ]; then
    echo "Error: Failed to fetch GitHub access token."
    echo "$resp_body"
    exit 1
fi

# --- 4. Create .netrc file for authentication ---
{
    echo "machine github.com login x-access-token password ${GH_TOKEN}"
    echo "machine api.github.com login x-access-token password ${GH_TOKEN}"
} > "$HOME/.netrc"
chmod 600 "$HOME/.netrc"
