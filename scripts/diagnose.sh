#!/bin/bash
###############################################################################
# Diagnostic Script - Check VM Status and Logs
#
# This script helps diagnose issues with the multi-tier deployment
# Run this after deployment to check status of both VMs
###############################################################################

set -e

PROJECT_ID="${1:-}"
ZONE="${2:-us-central1-a}"

if [ -z "$PROJECT_ID" ]; then
    echo "Usage: $0 <PROJECT_ID> [ZONE]"
    echo "Example: $0 leafy-glyph-479507-m4 us-central1-a"
    exit 1
fi

echo "=========================================="
echo "Multi-VM Deployment Diagnostics"
echo "=========================================="
echo "Project: $PROJECT_ID"
echo "Zone: $ZONE"
echo ""

# Function to run command on VM
run_on_vm() {
    local vm_name=$1
    local command=$2
    echo "Running on $vm_name: $command"
    gcloud compute ssh "$vm_name" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --command="$command" \
        2>&1
}

# Check VMs are running
echo "1. Checking VM Status..."
echo "----------------------------------------"
gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="zone:($ZONE)" \
    --format="table(name,status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"
echo ""

# Check Database VM
echo "2. Database VM Diagnostics..."
echo "----------------------------------------"

echo "2.1. PostgreSQL Service Status:"
run_on_vm "db-server" "sudo systemctl status postgresql --no-pager" || true
echo ""

echo "2.2. PostgreSQL Listening Ports:"
run_on_vm "db-server" "sudo ss -tuln | grep 5432" || echo "Port 5432 not listening!"
echo ""

echo "2.3. Database Startup Log (last 50 lines):"
run_on_vm "db-server" "sudo tail -50 /var/log/db-startup.log" || echo "Log file not found"
echo ""

echo "2.4. PostgreSQL Error Logs (last 20 lines):"
run_on_vm "db-server" "sudo tail -20 /var/log/postgresql/postgresql-15-main.log" || true
echo ""

echo "2.5. Test Database Connection:"
run_on_vm "db-server" "sudo -u postgres psql -c '\l'" || true
echo ""

echo "2.6. Check Startup Script Completion:"
run_on_vm "db-server" "ls -la /var/log/db-startup-complete.marker" || echo "Startup script may not have completed!"
echo ""

# Check Web VM
echo "3. Web VM Diagnostics..."
echo "----------------------------------------"

echo "3.1. Web Application Service Status:"
run_on_vm "web-server" "sudo systemctl status webapp --no-pager" || true
echo ""

echo "3.2. Nginx Service Status:"
run_on_vm "web-server" "sudo systemctl status nginx --no-pager" || true
echo ""

echo "3.3. Web Startup Log (last 50 lines):"
run_on_vm "web-server" "sudo tail -50 /var/log/web-startup.log" || echo "Log file not found"
echo ""

echo "3.4. Application Logs (last 30 lines):"
run_on_vm "web-server" "sudo journalctl -u webapp -n 30 --no-pager" || true
echo ""

echo "3.5. Application Error Logs:"
run_on_vm "web-server" "sudo journalctl -u webapp | grep -i error | tail -20" || echo "No errors found or service not started"
echo ""

echo "3.6. Check Startup Script Completion:"
run_on_vm "web-server" "ls -la /var/log/web-startup-complete.marker" || echo "Startup script may not have completed!"
echo ""

echo "3.7. Test Database Connectivity from Web VM:"
run_on_vm "web-server" "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/10.128.0.2/5432' && echo 'Database port is reachable' || echo 'Cannot reach database port!'"
echo ""

# Check Firewall Rules
echo "4. Firewall Rules..."
echo "----------------------------------------"
gcloud compute firewall-rules list \
    --project="$PROJECT_ID" \
    --filter="name~'allow.*tier'" \
    --format="table(name,allowed,sourceRanges,sourceTags,targetTags)"
echo ""

# Get Web IP and test endpoints
echo "5. Application Endpoints Test..."
echo "----------------------------------------"
WEB_IP=$(gcloud compute instances describe web-server \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

if [ -n "$WEB_IP" ]; then
    echo "Web Server IP: $WEB_IP"
    echo ""
    
    echo "5.1. Health Endpoint:"
    curl -s "http://$WEB_IP/api/health" | jq '.' || echo "Health check failed"
    echo ""
    
    echo "5.2. Database Status Endpoint:"
    curl -s "http://$WEB_IP/api/db-status" | jq '.' || echo "Database status check failed"
    echo ""
else
    echo "Could not determine web server IP"
fi

echo ""
echo "=========================================="
echo "Diagnostics Complete"
echo "=========================================="
echo ""
echo "Common Issues:"
echo "1. If PostgreSQL not running: SSH to db-server and run 'sudo systemctl restart postgresql'"
echo "2. If webapp not running: SSH to web-server and run 'sudo systemctl restart webapp'"
echo "3. If firewall blocking: Check firewall rules allow traffic on required ports"
echo "4. If startup scripts incomplete: Check for marker files and review logs"
echo ""
