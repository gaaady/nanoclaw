#!/usr/bin/env bash
# Set up Google Calendar access for a NanoClaw group.
#
# What this does:
#   1. Creates data/gcal/{group}/ to store OAuth tokens for this group
#   2. Runs gcalcli OAuth flow in your browser (scoped to one calendar)
#   3. Adds the mount to registered_groups.json so the container gets it
#
# Prerequisites:
#   - gcalcli installed: pip3 install gcalcli
#   - A Google Cloud project with Calendar API enabled
#   - OAuth2 Desktop credentials (client_secret_*.json) downloaded
#
# Usage:
#   ./my/setup-gcal.sh <group-folder> <path-to-client-secret.json>
#
# Example:
#   ./my/setup-gcal.sh main ~/Downloads/client_secret_xyz.json
#   ./my/setup-gcal.sh family-chat ~/Downloads/client_secret_xyz.json

set -euo pipefail

GROUP_FOLDER="${1:-}"
CLIENT_SECRET="${2:-}"

if [[ -z "$GROUP_FOLDER" || -z "$CLIENT_SECRET" ]]; then
  echo "Usage: $0 <group-folder> <path-to-client-secret.json>"
  echo ""
  echo "Example: $0 main ~/Downloads/client_secret_xyz.json"
  exit 1
fi

if [[ ! -f "$CLIENT_SECRET" ]]; then
  echo "Error: client secret file not found: $CLIENT_SECRET"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GCAL_DIR="$PROJECT_ROOT/data/gcal/$GROUP_FOLDER"
REGISTERED_GROUPS="$PROJECT_ROOT/data/registered_groups.json"

# ── 1. Create config directory ────────────────────────────────────────────────
mkdir -p "$GCAL_DIR"
cp "$CLIENT_SECRET" "$GCAL_DIR/client_secret.json"
echo "==> Created config dir: $GCAL_DIR"

# ── 2. Extract credentials and authenticate (browser flow) ───────────────────
CLIENT_ID=$(node -e "const s=JSON.parse(require('fs').readFileSync('$GCAL_DIR/client_secret.json'));const c=s.installed||s.web;console.log(c.client_id)")
CLIENT_SECRET=$(node -e "const s=JSON.parse(require('fs').readFileSync('$GCAL_DIR/client_secret.json'));const c=s.installed||s.web;console.log(c.client_secret)")

echo ""
echo "==> Opening browser for Google OAuth..."
echo "    Sign in and grant access to Google Calendar."
echo "    Only the calendar(s) you select will be accessible."
echo ""
gcalcli --config-folder "$GCAL_DIR" \
  --client-id "$CLIENT_ID" \
  --client-secret "$CLIENT_SECRET" \
  list

echo ""
echo "==> Auth complete."

# gcalcli sometimes saves to the default OS location instead of --config-folder.
# Copy it over if that happened.
DEFAULT_TOKEN="$HOME/Library/Application Support/gcalcli/oauth"  # macOS
LINUX_TOKEN="$HOME/.config/gcalcli/oauth"
if [[ ! -f "$GCAL_DIR/oauth" ]]; then
  if [[ -f "$DEFAULT_TOKEN" ]]; then
    cp "$DEFAULT_TOKEN" "$GCAL_DIR/oauth"
    echo "    Moved token from default location to $GCAL_DIR"
  elif [[ -f "$LINUX_TOKEN" ]]; then
    cp "$LINUX_TOKEN" "$GCAL_DIR/oauth"
    echo "    Moved token from default location to $GCAL_DIR"
  fi
fi
echo "    Tokens saved to $GCAL_DIR"

# ── 3. Wire into registered_groups.json ──────────────────────────────────────
if [[ ! -f "$REGISTERED_GROUPS" ]]; then
  echo ""
  echo "Warning: $REGISTERED_GROUPS not found."
  echo "Add this manually to the group's containerConfig once it's registered:"
  echo ""
  echo '  "containerConfig": {'
  echo '    "additionalMounts": [{'
  echo "      \"hostPath\": \"$GCAL_DIR\","
  echo '      "containerPath": "gcal",'
  echo '      "readonly": true'
  echo '    }]'
  echo '  }'
  exit 0
fi

# Use node to safely update the JSON
node - "$REGISTERED_GROUPS" "$GROUP_FOLDER" "$GCAL_DIR" <<'EOF'
const fs = require('fs');
const [,, file, folder, gcalDir] = process.argv;

const groups = JSON.parse(fs.readFileSync(file, 'utf8'));

const entry = Object.values(groups).find(g => g.folder === folder);
if (!entry) {
  console.error(`Group with folder "${folder}" not found in registered_groups.json.`);
  console.error('Register the group first, then re-run this script.');
  process.exit(1);
}

if (!entry.containerConfig) entry.containerConfig = {};
if (!entry.containerConfig.additionalMounts) entry.containerConfig.additionalMounts = [];

// Remove any existing gcal mount to avoid duplicates
entry.containerConfig.additionalMounts = entry.containerConfig.additionalMounts
  .filter(m => !m.containerPath || m.containerPath !== 'gcal');

entry.containerConfig.additionalMounts.push({
  hostPath: gcalDir,
  containerPath: 'gcal',
  readonly: true,
});

fs.writeFileSync(file, JSON.stringify(groups, null, 2) + '\n');
console.log(`Updated registered_groups.json — group "${folder}" now has calendar access.`);
EOF

echo ""
echo "==> Done!"
echo ""
echo "    The agent in '$GROUP_FOLDER' can now use gcalcli."
echo "    Rebuild the container and restart NanoClaw:"
echo ""
echo "    ./container/build.sh"
echo "    # macOS: launchctl kickstart -k gui/\$(id -u)/com.nanoclaw"
echo "    # Linux: systemctl --user restart nanoclaw"
