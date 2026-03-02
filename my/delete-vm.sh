#!/usr/bin/env bash
# Stops the NanoClaw VM and releases the static IP.
# WARNING: This permanently deletes the VM and its disk.

set -euo pipefail

INSTANCE_NAME="nanoclaw"
ZONE="us-central1-a"
REGION="us-central1"
STATIC_IP_NAME="${INSTANCE_NAME}-ip"

export CLOUDSDK_PYTHON=/opt/homebrew/opt/python@3.12/libexec/bin/python3

echo "WARNING: This will permanently delete '$INSTANCE_NAME' and release the static IP."
read -r -p "Type the instance name to confirm: " CONFIRM
if [[ "$CONFIRM" != "$INSTANCE_NAME" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "==> Deleting VM: $INSTANCE_NAME..."
gcloud compute instances delete "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --quiet

echo ""
echo "==> Releasing static IP: $STATIC_IP_NAME..."
gcloud compute addresses delete "$STATIC_IP_NAME" \
  --region="$REGION" \
  --quiet 2>/dev/null || echo "    (static IP not found, skipping)"

echo ""
echo "==> Done. VM and IP have been removed."
