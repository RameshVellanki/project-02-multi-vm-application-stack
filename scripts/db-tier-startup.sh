#!/bin/bash
###############################################################################
# Database Tier Startup Script
# 
# This script configures PostgreSQL database server:
# 1. Install PostgreSQL 15
# 2. Configure for network access from web tier
# 3. Create database and user
# 4. Initialize schema
###############################################################################

set -e

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/db-startup.log
}

log "Starting database tier setup..."

# Get metadata
DB_NAME=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-name -H "Metadata-Flavor: Google")
DB_USER=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-user -H "Metadata-Flavor: Google")
DB_PASSWORD=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-password -H "Metadata-Flavor: Google")

log "Database configuration: DB=$DB_NAME, USER=$DB_USER"

# Update package lists
log "Updating package lists..."
apt-get update

# Install PostgreSQL 15
log "Installing PostgreSQL 15..."
apt-get install -y postgresql-15 postgresql-contrib-15

# Wait for PostgreSQL to start
log "Waiting for PostgreSQL to start..."
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL is active"
        break
    fi
    COUNT=$((COUNT + 1))
    sleep 1
done

if ! systemctl is-active --quiet postgresql; then
    log "❌ PostgreSQL failed to start in ${MAX_WAIT} seconds"
    exit 1
fi

# Wait for PostgreSQL to be ready to accept connections
log "Waiting for PostgreSQL to accept connections..."
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        log "✅ PostgreSQL is accepting connections"
        break
    fi
    COUNT=$((COUNT + 1))
    sleep 1
done

# Configure PostgreSQL to listen on all interfaces
log "Configuring PostgreSQL network settings..."
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/15/main/postgresql.conf

# Configure authentication for web tier
log "Configuring PostgreSQL authentication..."
cat >> /etc/postgresql/15/main/pg_hba.conf <<EOF

# Allow connections from web tier (internal network)
host    all             all             10.128.0.0/9            md5
host    all             all             172.16.0.0/12           md5
host    all             all             192.168.0.0/16          md5
EOF

# Restart PostgreSQL to apply changes
log "Restarting PostgreSQL..."
systemctl restart postgresql

# Create database user and database
log "Creating database and user..."
sudo -u postgres psql <<EOF
-- Create user
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

\c $DB_NAME

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF

# Create application schema
log "Creating application schema..."
sudo -u postgres psql -d $DB_NAME <<EOF
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Grant table permissions to app user
GRANT ALL PRIVILEGES ON TABLE users TO $DB_USER;
GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO $DB_USER;

-- Insert sample data
INSERT INTO users (name, email) VALUES
    ('Alice Johnson', 'alice@example.com'),
    ('Bob Smith', 'bob@example.com'),
    ('Carol Williams', 'carol@example.com')
ON CONFLICT (email) DO NOTHING;

-- Create function to update timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
\$\$ language 'plpgsql';

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();
EOF

# Verify database setup
log "Verifying database setup..."
sudo -u postgres psql -d $DB_NAME -c "\dt" | tee -a /var/log/db-startup.log
sudo -u postgres psql -d $DB_NAME -c "SELECT COUNT(*) FROM users;" | tee -a /var/log/db-startup.log

# Enable PostgreSQL on boot
log "Enabling PostgreSQL on boot..."
systemctl enable postgresql

# Create monitoring script
log "Creating database monitoring script..."
cat > /usr/local/bin/db-monitor.sh <<'MONITOR_EOF'
#!/bin/bash
while true; do
    if ! systemctl is-active --quiet postgresql; then
        echo "[$(date)] PostgreSQL is down, attempting restart..."
        systemctl restart postgresql
    fi
    sleep 30
done
MONITOR_EOF

chmod +x /usr/local/bin/db-monitor.sh

# Create systemd service for monitoring
cat > /etc/systemd/system/db-monitor.service <<'SERVICE_EOF'
[Unit]
Description=PostgreSQL Health Monitor
After=postgresql.service

[Service]
Type=simple
ExecStart=/usr/local/bin/db-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Enable and start monitoring service
systemctl daemon-reload
systemctl enable db-monitor.service
systemctl start db-monitor.service

# Display database information
log "==============================================="
log "Database Tier Setup Complete!"
log "==============================================="
log "PostgreSQL version: $(sudo -u postgres psql --version | cut -d' ' -f3)"
log "Database name: $DB_NAME"
log "Database user: $DB_USER"
log "Service status: $(systemctl is-active postgresql)"
log "Listening on: $(grep listen_addresses /etc/postgresql/15/main/postgresql.conf | grep -v '#')"
log "Active connections: $(ss -tuln | grep :5432 || echo 'Port 5432 not yet bound')"
log "Test connection: $(sudo -u postgres psql -c 'SELECT version();' 2>&1 | head -1)"
log "==============================================="

# Final connectivity test
log "Performing final connectivity test..."
if sudo -u postgres psql -d $DB_NAME -c "SELECT COUNT(*) FROM users;" > /dev/null 2>&1; then
    log "✅ Database is fully operational and accepting queries"
else
    log "⚠️  WARNING: Database connectivity test failed"
fi

# Create completion marker
touch /var/log/db-startup-complete.marker
log "Startup completion marker created"

log "Database tier startup completed successfully"
exit 0
