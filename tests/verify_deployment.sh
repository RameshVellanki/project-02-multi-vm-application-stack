#!/bin/bash
###############################################################################
# Deployment Verification Script
#
# This script verifies that the multi-tier application is properly deployed
# and functioning correctly. It performs health checks with appropriate timeouts
# to allow for startup time.
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WEB_IP="${1:-}"
MAX_WAIT_TIME=600  # 10 minutes total wait time
CHECK_INTERVAL=30  # Check every 30 seconds

if [ -z "$WEB_IP" ]; then
    echo -e "${RED}❌ Error: Web IP address not provided${NC}"
    echo "Usage: $0 <WEB_IP_ADDRESS>"
    exit 1
fi

echo "==========================================="
echo "Multi-VM Application Deployment Verification"
echo "==========================================="
echo "Web Server IP: $WEB_IP"
echo "Max Wait Time: ${MAX_WAIT_TIME}s"
echo "Check Interval: ${CHECK_INTERVAL}s"
echo "==========================================="
echo ""

# Function to check endpoint
check_endpoint() {
    local url=$1
    local description=$2
    local max_retries=$((MAX_WAIT_TIME / CHECK_INTERVAL))
    local retry_count=0
    
    echo -e "${YELLOW}⏳ Testing $description...${NC}"
    
    while [ $retry_count -lt $max_retries ]; do
        if response=$(curl -f -s -w "\n%{http_code}" "$url" 2>/dev/null); then
            http_code=$(echo "$response" | tail -n 1)
            body=$(echo "$response" | sed '$d')
            
            if [ "$http_code" = "200" ]; then
                echo -e "${GREEN}✅ $description - SUCCESS${NC}"
                echo "Response: $body" | jq '.' 2>/dev/null || echo "$body"
                return 0
            fi
        else
            # Also try without -f flag to see what status code we get
            response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null)
            http_code=$(echo "$response" | tail -n 1)
            body=$(echo "$response" | sed '$d')
            
            # 503 Service Unavailable might mean app is running but DB not ready
            if [ "$http_code" = "503" ]; then
                echo "   Received 503 - Service starting (database may not be ready yet)"
                if echo "$body" | grep -q '"connected":false' 2>/dev/null; then
                    echo "   Database connection issue detected, will retry..."
                fi
            fi
        fi
        
        retry_count=$((retry_count + 1))
        elapsed=$((retry_count * CHECK_INTERVAL))
        echo "   Attempt $retry_count/$max_retries (${elapsed}s elapsed)..."
        
        if [ $retry_count -lt $max_retries ]; then
            sleep $CHECK_INTERVAL
        fi
    done
    
    echo -e "${RED}❌ $description - FAILED after ${MAX_WAIT_TIME}s${NC}"
    return 1
}

# Function to check if endpoint exists (even if app not ready)
check_connectivity() {
    local url=$1
    echo -e "${YELLOW}⏳ Checking basic connectivity to $url...${NC}"
    
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Server is reachable${NC}"
        return 0
    else
        echo -e "${RED}❌ Cannot connect to server${NC}"
        return 1
    fi
}

# Test 1: Basic connectivity
echo "Test 1: Basic Connectivity"
echo "-------------------------------------------"
check_connectivity "http://$WEB_IP" || {
    echo -e "${RED}❌ CRITICAL: Cannot reach web server at $WEB_IP${NC}"
    echo "Possible issues:"
    echo "  - Firewall rules not properly configured"
    echo "  - VM instance not running"
    echo "  - Incorrect IP address"
    exit 1
}
echo ""

# Test 2: Root endpoint
echo "Test 2: Root Endpoint (Web UI)"
echo "-------------------------------------------"
if curl -f -s "http://$WEB_IP/" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Root endpoint accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Root endpoint not yet ready (application may still be starting)${NC}"
fi
echo ""

# Test 3: Health check endpoint
echo "Test 3: Health Check Endpoint"
echo "-------------------------------------------"
check_endpoint "http://$WEB_IP/api/health" "Health Check" || {
    echo -e "${RED}❌ Health check failed${NC}"
    echo "This likely means:"
    echo "  - Node.js application hasn't started yet"
    echo "  - Application crashed during startup"
    echo "  - Nginx reverse proxy not configured"
    echo ""
    echo "To debug, SSH into the web VM and run:"
    echo "  sudo journalctl -u webapp -n 100"
    echo "  sudo systemctl status webapp"
    echo "  sudo systemctl status nginx"
    exit 1
}
echo ""

# Test 4: Database connectivity check
echo "Test 4: Database Connectivity"
echo "-------------------------------------------"
check_endpoint "http://$WEB_IP/api/db-status" "Database Status" || {
    echo -e "${RED}❌ Database connectivity check failed${NC}"
    echo "This likely means:"
    echo "  - Database VM not running or not ready"
    echo "  - PostgreSQL service not started"
    echo "  - Network connectivity issues between tiers"
    echo "  - Database credentials incorrect"
    echo ""
    echo "To debug, check:"
    echo "  1. DB VM: sudo systemctl status postgresql"
    echo "  2. DB VM: sudo -u postgres psql -c '\\l'"
    echo "  3. Web VM: sudo journalctl -u webapp -n 100 | grep -i error"
    exit 1
}
echo ""

# Test 5: User API endpoints
echo "Test 5: User Management API"
echo "-------------------------------------------"

# List users
echo -e "${YELLOW}⏳ Testing GET /api/users...${NC}"
if response=$(curl -f -s "http://$WEB_IP/api/users"); then
    echo -e "${GREEN}✅ List users - SUCCESS${NC}"
    echo "$response" | jq '.'
else
    echo -e "${RED}❌ List users - FAILED${NC}"
    exit 1
fi
echo ""

# Create a test user
echo -e "${YELLOW}⏳ Testing POST /api/users...${NC}"
if response=$(curl -f -s -X POST "http://$WEB_IP/api/users" \
    -H "Content-Type: application/json" \
    -d '{"name":"Test User","email":"test@example.com"}'); then
    echo -e "${GREEN}✅ Create user - SUCCESS${NC}"
    echo "$response" | jq '.'
    user_id=$(echo "$response" | jq -r '.data.id')
else
    echo -e "${RED}❌ Create user - FAILED${NC}"
    exit 1
fi
echo ""

# Get the created user
if [ -n "$user_id" ]; then
    echo -e "${YELLOW}⏳ Testing GET /api/users/$user_id...${NC}"
    if response=$(curl -f -s "http://$WEB_IP/api/users/$user_id"); then
        echo -e "${GREEN}✅ Get user by ID - SUCCESS${NC}"
        echo "$response" | jq '.'
    else
        echo -e "${RED}❌ Get user by ID - FAILED${NC}"
        exit 1
    fi
    echo ""
    
    # Update the user
    echo -e "${YELLOW}⏳ Testing PUT /api/users/$user_id...${NC}"
    if response=$(curl -f -s -X PUT "http://$WEB_IP/api/users/$user_id" \
        -H "Content-Type: application/json" \
        -d '{"name":"Updated User"}'); then
        echo -e "${GREEN}✅ Update user - SUCCESS${NC}"
        echo "$response" | jq '.'
    else
        echo -e "${RED}❌ Update user - FAILED${NC}"
        exit 1
    fi
    echo ""
    
    # Delete the user
    echo -e "${YELLOW}⏳ Testing DELETE /api/users/$user_id...${NC}"
    if response=$(curl -f -s -X DELETE "http://$WEB_IP/api/users/$user_id"); then
        echo -e "${GREEN}✅ Delete user - SUCCESS${NC}"
        echo "$response" | jq '.'
    else
        echo -e "${RED}❌ Delete user - FAILED${NC}"
        exit 1
    fi
    echo ""
fi

# Final summary
echo "==========================================="
echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
echo "==========================================="
echo "Deployment verified successfully!"
echo ""
echo "Your application is accessible at:"
echo "  🌐 Web UI: http://$WEB_IP"
echo "  📊 Health: http://$WEB_IP/api/health"
echo "  💾 DB Status: http://$WEB_IP/api/db-status"
echo "  👥 Users API: http://$WEB_IP/api/users"
echo "==========================================="

exit 0
