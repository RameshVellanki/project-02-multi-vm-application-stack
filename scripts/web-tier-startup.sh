#!/bin/bash
###############################################################################
# Web Tier Startup Script
# 
# This script configures the web application server:
# 1. Install Node.js and Nginx
# 2. Deploy Node.js application
# 3. Configure Nginx reverse proxy
# 4. Start application service
###############################################################################

set -e

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/web-startup.log
}

log "Starting web tier setup..."

# Get metadata
DB_HOST=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-host -H "Metadata-Flavor: Google")
DB_PORT=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-port -H "Metadata-Flavor: Google")
DB_NAME=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-name -H "Metadata-Flavor: Google")
DB_USER=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-user -H "Metadata-Flavor: Google")
DB_PASSWORD=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-password -H "Metadata-Flavor: Google")
APP_PORT=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/app-port -H "Metadata-Flavor: Google")

log "Configuration: DB_HOST=$DB_HOST, DB_PORT=$DB_PORT, APP_PORT=$APP_PORT"

# Update package lists
log "Updating package lists..."
apt-get update

# Install Node.js 18.x
log "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Nginx
log "Installing Nginx..."
apt-get install -y nginx

# Create application directory
log "Creating application directory..."
mkdir -p /opt/webapp
cd /opt/webapp

# Create package.json
log "Creating Node.js application..."
cat > package.json <<EOF
{
  "name": "multi-vm-webapp",
  "version": "1.0.0",
  "description": "Multi-tier web application for GCP learning",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "body-parser": "^1.20.2"
  }
}
EOF

# Create application server
cat > server.js <<'NODEJS_EOF'
const express = require('express');
const bodyParser = require('body-parser');
const { Pool } = require('pg');

const app = express();
const port = process.env.APP_PORT || 3000;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Database configuration with better connection handling
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,  // Increased from 2s to 10s
  ssl: false,
  // Retry connection configuration
  keepAlive: true,
  keepAliveInitialDelayMillis: 10000
});

// Database connection status
let dbConnected = false;

// Test database connection with retry logic
const testDatabaseConnection = async (retries = 10, delay = 5000) => {
  for (let i = 0; i < retries; i++) {
    try {
      console.log(`Attempting database connection (attempt ${i + 1}/${retries})...`);
      const client = await pool.connect();
      await client.query('SELECT 1');
      client.release();
      console.log('✅ Successfully connected to PostgreSQL database');
      dbConnected = true;
      return true;
    } catch (err) {
      console.error(`❌ Database connection attempt ${i + 1} failed:`, err.message);
      if (i < retries - 1) {
        console.log(`Retrying in ${delay / 1000} seconds...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  console.error('Failed to connect to database after all retries');
  dbConnected = false;
  return false;
};

// Connection event handlers
pool.on('connect', (client) => {
  console.log('New database connection established');
  dbConnected = true;
});

pool.on('error', (err, client) => {
  console.error('Unexpected database error:', err);
  dbConnected = false;
});

pool.on('remove', (client) => {
  console.log('Database connection removed from pool');
});

// Health check endpoint (always available)
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    tier: 'web',
    nodejs: process.version,
    uptime: process.uptime(),
    database: dbConnected ? 'connected' : 'disconnected'
  });
});

// Database status endpoint with better error handling
app.get('/api/db-status', async (req, res) => {
  try {
    const result = await pool.query('SELECT COUNT(*) as count FROM users');
    res.json({
      connected: true,
      database: process.env.DB_NAME,
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      tables: ['users'],
      recordCount: parseInt(result.rows[0].count)
    });
  } catch (err) {
    console.error('Database error:', err);
    res.status(503).json({
      connected: false,
      error: err.message,
      code: err.code,
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      database: process.env.DB_NAME
    });
  }
});

// Get all users
app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query('SELECT id, name, email, created_at FROM users ORDER BY id');
    res.json({
      success: true,
      count: result.rows.length,
      data: result.rows
    });
  } catch (err) {
    console.error('Error fetching users:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// Get user by ID
app.get('/api/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT id, name, email, created_at FROM users WHERE id = $1', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }
    
    res.json({
      success: true,
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error fetching user:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// Create new user
app.post('/api/users', async (req, res) => {
  try {
    const { name, email } = req.body;
    
    if (!name || !email) {
      return res.status(400).json({
        success: false,
        error: 'Name and email are required'
      });
    }
    
    const result = await pool.query(
      'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at',
      [name, email]
    );
    
    res.status(201).json({
      success: true,
      message: 'User created successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error creating user:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// Update user
app.put('/api/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, email } = req.body;
    
    const result = await pool.query(
      'UPDATE users SET name = COALESCE($1, name), email = COALESCE($2, email) WHERE id = $3 RETURNING id, name, email, updated_at',
      [name, email, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }
    
    res.json({
      success: true,
      message: 'User updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating user:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// Delete user
app.delete('/api/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM users WHERE id = $1 RETURNING id', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }
    
    res.json({
      success: true,
      message: 'User deleted successfully',
      id: result.rows[0].id
    });
  } catch (err) {
    console.error('Error deleting user:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// Root endpoint
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Multi-VM Application Stack</title>
      <style>
        body { 
          font-family: Arial, sans-serif; 
          max-width: 800px; 
          margin: 50px auto; 
          padding: 20px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
        }
        .container {
          background: rgba(255, 255, 255, 0.1);
          padding: 30px;
          border-radius: 10px;
          backdrop-filter: blur(10px);
        }
        h1 { color: #fff; }
        .endpoint { 
          background: rgba(255, 255, 255, 0.2);
          padding: 10px;
          margin: 10px 0;
          border-radius: 5px;
        }
        code {
          background: rgba(0, 0, 0, 0.3);
          padding: 2px 6px;
          border-radius: 3px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🚀 Multi-VM Application Stack</h1>
        <h2>Project 2 - Web + Database Tier</h2>
        
        <h3>Available API Endpoints:</h3>
        <div class="endpoint"><code>GET /api/health</code> - Health check</div>
        <div class="endpoint"><code>GET /api/db-status</code> - Database status</div>
        <div class="endpoint"><code>GET /api/users</code> - List all users</div>
        <div class="endpoint"><code>GET /api/users/:id</code> - Get user by ID</div>
        <div class="endpoint"><code>POST /api/users</code> - Create new user</div>
        <div class="endpoint"><code>PUT /api/users/:id</code> - Update user</div>
        <div class="endpoint"><code>DELETE /api/users/:id</code> - Delete user</div>
        
        <h3>Architecture:</h3>
        <ul>
          <li>✅ Web Tier: Node.js + Express + Nginx</li>
          <li>✅ Database Tier: PostgreSQL 15</li>
          <li>✅ Network: Internal communication</li>
          <li>✅ IAM: Separate service accounts</li>
        </ul>
      </div>
    </body>
    </html>
  `);
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found'
  });
});

// Start server function
const startServer = async () => {
  try {
    // Test database connection before starting server
    console.log('Testing database connection before starting server...');
    await testDatabaseConnection(10, 5000);
    
    // Start Express server
    app.listen(port, '0.0.0.0', () => {
      console.log('===============================================');
      console.log(`✅ Web application listening on port ${port}`);
      console.log(`Database: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
      console.log(`Database Status: ${dbConnected ? 'Connected' : 'Disconnected (will retry)'}`);
      console.log('===============================================');
    });
    
    // Continue trying to connect to database even if initial attempts fail
    if (!dbConnected) {
      console.log('Server started but database not connected. Will continue retrying in background...');
      setInterval(async () => {
        if (!dbConnected) {
          console.log('Background database reconnection attempt...');
          await testDatabaseConnection(1, 1000);
        }
      }, 30000); // Retry every 30 seconds
    }
  } catch (err) {
    console.error('Error starting server:', err);
    process.exit(1);
  }
};

// Start the application
startServer();

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, closing server...');
  pool.end();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, closing server...');
  pool.end();
  process.exit(0);
});
NODEJS_EOF

# Install Node.js dependencies
log "Installing Node.js dependencies..."
npm install --production

# Create environment file for systemd service
cat > /opt/webapp/.env <<EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
APP_PORT=$APP_PORT
NODE_ENV=production
EOF

# Test database connectivity before starting application
log "Testing database connectivity..."
MAX_DB_WAIT=120  # Wait up to 2 minutes for database
DB_WAIT_COUNT=0
DB_AVAILABLE=false

while [ $DB_WAIT_COUNT -lt $MAX_DB_WAIT ]; do
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
        log "✅ Database is reachable at $DB_HOST:$DB_PORT"
        DB_AVAILABLE=true
        break
    else
        DB_WAIT_COUNT=$((DB_WAIT_COUNT + 5))
        log "Waiting for database... ($DB_WAIT_COUNT/$MAX_DB_WAIT seconds)"
        sleep 5
    fi
done

if [ "$DB_AVAILABLE" = false ]; then
    log "⚠️  WARNING: Database not reachable after ${MAX_DB_WAIT}s. Starting app anyway (will retry connection)."
else
    log "Database connectivity verified!"
fi

# Create systemd service for Node.js app
log "Creating systemd service for application..."
cat > /etc/systemd/system/webapp.service <<EOF
[Unit]
Description=Multi-VM Web Application
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/webapp
EnvironmentFile=/opt/webapp/.env
ExecStart=/usr/bin/node /opt/webapp/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the application
log "Starting Node.js application..."
systemctl daemon-reload
systemctl enable webapp.service
systemctl start webapp.service

# Wait for app to start
sleep 5

# Configure Nginx as reverse proxy
log "Configuring Nginx reverse proxy..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Test Nginx configuration
log "Testing Nginx configuration..."
nginx -t

# Enable and restart Nginx
log "Starting Nginx..."
systemctl enable nginx
systemctl restart nginx

# Verify services are running
log "Verifying services..."
sleep 3

if systemctl is-active --quiet webapp; then
    log "✅ Node.js application is running"
else
    log "❌ ERROR: Node.js application failed to start"
    journalctl -u webapp -n 50
fi

if systemctl is-active --quiet nginx; then
    log "✅ Nginx is running"
else
    log "❌ ERROR: Nginx failed to start"
fi

# Display service information
log "==============================================="
log "Web Tier Setup Complete!"
log "==============================================="
log "Node.js version: $(node --version)"
log "NPM version: $(npm --version)"
log "Application status: $(systemctl is-active webapp)"
log "Nginx status: $(systemctl is-active nginx)"
log "Application port: $APP_PORT"
log "Database connection: $DB_HOST:$DB_PORT/$DB_NAME"
log "Database reachable: $(timeout 2 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT" && echo 'YES' || echo 'NO')"
log "==============================================="

# Create completion marker
touch /var/log/web-startup-complete.marker
log "Startup completion marker created"

log "Web tier startup completed successfully"
exit 0
