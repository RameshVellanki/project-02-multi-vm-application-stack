#!/bin/bash
###############################################################################
# Check VM Serial Console Output
#
# This script checks the serial console logs to see startup script progress
# Useful when VMs are not accessible via SSH yet
###############################################################################

PROJECT_ID="${1:-}"
ZONE="${2:-us-central1-a}"
VM_NAME="${3:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <PROJECT_ID> <ZONE> <VM_NAME>"
    echo "Example: $0 my-project us-central1-a db-server"
    exit 1
fi

echo "=========================================="
echo "Serial Console Output for $VM_NAME"
echo "=========================================="
echo ""

gcloud compute instances get-serial-port-output "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --start=-50000 \
    2>&1 | tail -200

echo ""
echo "=========================================="
echo "Last 200 lines of serial console"
echo "=========================================="
