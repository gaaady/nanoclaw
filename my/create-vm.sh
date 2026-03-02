#!/usr/bin/env bash
# Creates a GCP free-tier e2-micro VM for NanoClaw.
# Free tier requirements: e2-micro in us-central1/us-east1/us-west1,
# 30 GB pd-standard disk, standard network egress only.

set -euo pipefail

INSTANCE_NAME="nanoclaw"
ZONE="us-central1-a"
REGION="us-central1"
MACHINE_TYPE="e2-micro"
DISK_SIZE="30GB"
DISK_TYPE="pd-standard"
STATIC_IP_NAME="${INSTANCE_NAME}-ip"

# Debian 12 (Bookworm) — leaner than Ubuntu (~150 MB idle vs ~280 MB),
# better fit for 1 GB RAM on e2-micro.
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"

export CLOUDSDK_PYTHON=/opt/homebrew/opt/python@3.12/libexec/bin/python3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARDEN_SCRIPT="$SCRIPT_DIR/harden.sh"

echo "==> Creating VM: $INSTANCE_NAME ($MACHINE_TYPE, $ZONE)"

gcloud compute instances create "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size="$DISK_SIZE" \
  --boot-disk-type="$DISK_TYPE" \
  --tags=nanoclaw \
  --metadata=enable-oslogin=TRUE \
  --metadata-from-file=startup-script="$HARDEN_SCRIPT"

echo ""
echo "==> Opening firewall for SSH..."
gcloud compute firewall-rules create allow-ssh-nanoclaw \
  --allow=tcp:22 \
  --target-tags=nanoclaw \
  --description="Allow SSH to NanoClaw" \
  --quiet 2>/dev/null || echo "    (firewall rule already exists, skipping)"

echo ""
echo "==> Reserving static IP: $STATIC_IP_NAME..."
gcloud compute addresses create "$STATIC_IP_NAME" \
  --region="$REGION" \
  --quiet 2>/dev/null || echo "    (static IP already exists, skipping)"

STATIC_IP=$(gcloud compute addresses describe "$STATIC_IP_NAME" \
  --region="$REGION" \
  --format='get(address)')

echo "    Reserved: $STATIC_IP"

echo ""
echo "==> Attaching static IP to VM..."
gcloud compute instances delete-access-config "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --access-config-name="external-nat" \
  --quiet
gcloud compute instances add-access-config "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --access-config-name="external-nat" \
  --address="$STATIC_IP" \
  --quiet

echo ""
echo "==> Done."
echo ""
echo "    SSH:    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "    IP:     $STATIC_IP"
echo ""
echo "    Hardening runs in background on first boot."
echo "    Check: sudo tail -f /var/log/nanoclaw-harden.log"
