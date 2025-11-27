# Database Connection Improvements

## Problem
The web tier was attempting to connect to the database at `10.128.0.2:5432` but received `ECONNREFUSED` errors because:
1. The database server wasn't fully initialized when the web server started
2. PostgreSQL hadn't started accepting network connections
3. The Node.js app had insufficient retry logic

## Solutions Implemented

### 1. **Database Tier Improvements** (`db-tier-startup.sh`)

#### Better PostgreSQL Startup Verification
- Added active waiting loop to confirm PostgreSQL service is running
- Verifies PostgreSQL is accepting connections before continuing
- Maximum wait time of 30 seconds with status checks every second

```bash
# Wait for PostgreSQL to accept connections
while [ $COUNT -lt $MAX_WAIT ]; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        log "✅ PostgreSQL is accepting connections"
        break
    fi
    COUNT=$((COUNT + 1))
    sleep 1
done
```

#### Enhanced Logging
- Added port binding verification using `ss -tuln | grep :5432`
- Test connection with actual query before completing setup
- Confirms database is fully operational before script exits

### 2. **Web Tier Improvements** (`web-tier-startup.sh`)

#### Pre-Flight Database Connectivity Check
- Tests if database port is reachable before starting Node.js app
- Waits up to 2 minutes for database to become available
- Uses TCP connection test: `cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT`

```bash
# Test database connectivity before starting application
MAX_DB_WAIT=120  # Wait up to 2 minutes
while [ $DB_WAIT_COUNT -lt $MAX_DB_WAIT ]; do
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT"; then
        DB_AVAILABLE=true
        break
    fi
    sleep 5
done
```

#### Node.js Application Retry Logic
Enhanced the application with:

**Increased Connection Timeout**
```javascript
connectionTimeoutMillis: 10000,  // Increased from 2s to 10s
```

**Database Connection Test Function**
```javascript
const testDatabaseConnection = async (retries = 10, delay = 5000) => {
  for (let i = 0; i < retries; i++) {
    try {
      const client = await pool.connect();
      await client.query('SELECT 1');
      client.release();
      return true;
    } catch (err) {
      if (i < retries - 1) {
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  return false;
};
```

**Application Startup with Database Check**
- Tests database connection 10 times with 5-second delays (50 seconds total)
- Server starts even if database isn't ready (for resilience)
- Background retry every 30 seconds if initial connection fails

**Better Error Reporting**
- Health endpoint now includes database connection status
- Database status endpoint returns 503 (Service Unavailable) instead of 500
- Detailed error information including error code and connection details

### 3. **Test Script Improvements** (`verify_deployment.sh`)

#### Handle 503 Status Codes
- Recognizes 503 as "service starting" rather than complete failure
- Detects `"connected":false` in response to identify database issues
- Provides better diagnostic messages during retries

```bash
# 503 Service Unavailable might mean app is running but DB not ready
if [ "$http_code" = "503" ]; then
    echo "   Received 503 - Service starting (database may not be ready yet)"
fi
```

### 4. **Systemd Service Configuration**

#### Web Application Service
Added network dependency:
```ini
[Unit]
Description=Multi-VM Web Application
After=network.target
Wants=network-online.target
```

This ensures the network is fully available before starting the application.

## Timeline

With these improvements, the typical startup sequence is:

1. **Database Tier** (60-90 seconds)
   - Install PostgreSQL: ~30-45s
   - Configure and restart: ~10-15s
   - Verify connections: ~5s
   - Create schema and data: ~10-20s

2. **Web Tier** (90-120 seconds)
   - Install Node.js and Nginx: ~40-60s
   - Install npm packages: ~20-30s
   - Wait for database: 0-120s (depends on DB readiness)
   - Start application: ~5-10s

3. **Total Expected Time**: 3-5 minutes

## Testing After Deployment

### Quick Test (from local machine)
```bash
WEB_IP="<your-web-ip>"

# Wait 5 minutes after terraform apply
sleep 300

# Test health (should always work)
curl http://$WEB_IP/api/health

# Test database (might return 503 initially)
curl http://$WEB_IP/api/db-status
```

### Comprehensive Test
```bash
# Run the verification script
./tests/verify_deployment.sh $WEB_IP
```

## Troubleshooting

### If database connection still fails:

1. **Check database is running:**
   ```bash
   gcloud compute ssh db-server --zone=us-central1-a
   sudo systemctl status postgresql
   sudo -u postgres psql -c '\l'
   ```

2. **Check port is listening:**
   ```bash
   sudo ss -tuln | grep 5432
   sudo netstat -an | grep 5432
   ```

3. **Check web tier can reach database:**
   ```bash
   gcloud compute ssh web-server --zone=us-central1-a
   ping 10.128.0.2
   telnet 10.128.0.2 5432
   ```

4. **Check application logs:**
   ```bash
   sudo journalctl -u webapp -n 100 --no-pager
   sudo journalctl -u webapp | grep -i "database\|error"
   ```

5. **Check firewall rules:**
   ```bash
   gcloud compute firewall-rules list | grep postgres
   ```

## Key Benefits

✅ **Resilient startup** - Web tier waits for database before starting
✅ **Better error handling** - 503 status codes indicate service is starting
✅ **Automatic retry** - Background reconnection attempts every 30 seconds
✅ **Detailed logging** - Easy to diagnose issues from logs
✅ **Graceful degradation** - Health endpoint works even if database is down
