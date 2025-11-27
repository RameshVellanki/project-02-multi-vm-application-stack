# Debugging Database Connection Issues

## Quick Diagnosis

If the deployment succeeds but database connectivity tests fail after 10 minutes, follow these steps:

### 1. Check VM Status

```bash
cd terraform
PROJECT_ID=$(terraform output -raw project_id)
ZONE=$(terraform output -raw zone)

# List VMs
gcloud compute instances list --project=$PROJECT_ID --filter="zone:$ZONE"
```

Both VMs should show status `RUNNING`.

### 2. Check Serial Console Logs

The startup scripts write to the serial console. Check if they completed:

```bash
# Database server logs
gcloud compute instances get-serial-port-output db-server \
  --zone=$ZONE \
  --project=$PROJECT_ID | grep -A 5 "Database tier startup completed"

# Web server logs  
gcloud compute instances get-serial-port-output web-server \
  --zone=$ZONE \
  --project=$PROJECT_ID | grep -A 5 "Web tier startup completed"
```

### 3. SSH and Check Services

#### Database Server

```bash
# SSH into database server
gcloud compute ssh db-server --zone=$ZONE --project=$PROJECT_ID

# Check PostgreSQL status
sudo systemctl status postgresql

# Check if port is listening
sudo ss -tuln | grep 5432

# Test database connection
sudo -u postgres psql -c '\l'

# Check startup log
sudo tail -100 /var/log/db-startup.log

# Check for completion marker
ls -la /var/log/db-startup-complete.marker
```

#### Web Server

```bash
# SSH into web server
gcloud compute ssh web-server --zone=$ZONE --project=$PROJECT_ID

# Check webapp status
sudo systemctl status webapp

# Check Nginx status
sudo systemctl status nginx

# Check application logs
sudo journalctl -u webapp -n 100 --no-pager

# Check for errors
sudo journalctl -u webapp | grep -i error

# Check startup log
sudo tail -100 /var/log/web-startup.log

# Check for completion marker
ls -la /var/log/web-startup-complete.marker

# Test database connectivity
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/10.128.0.2/5432' && echo "DB reachable" || echo "DB not reachable"
```

### 4. Manual Restart if Needed

If services haven't started:

#### Restart Database

```bash
# On db-server
sudo systemctl restart postgresql
sudo systemctl status postgresql
```

#### Restart Web Application

```bash
# On web-server
sudo systemctl restart webapp
sudo journalctl -u webapp -f  # Follow logs
```

### 5. Test Endpoints Manually

```bash
WEB_IP=$(terraform -chdir=./terraform output -raw web_server_external_ip)

# Health check (should always work if web server is running)
curl http://$WEB_IP/api/health

# Database status (will show connection details or errors)
curl http://$WEB_IP/api/db-status
```

## Common Issues

### Issue 1: PostgreSQL Not Installed

**Symptom:** `postgresql.service not found`

**Solution:** Re-run startup script or manually install:
```bash
sudo apt-get update
sudo apt-get install -y postgresql-15
```

### Issue 2: PostgreSQL Not Listening on Network

**Symptom:** Port 5432 only bound to localhost

**Check:**
```bash
sudo -u postgres psql -c "SHOW listen_addresses;"
```

**Fix:**
```bash
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/15/main/postgresql.conf
sudo systemctl restart postgresql
```

### Issue 3: Firewall Blocking Internal Traffic

**Symptom:** Web can't reach database even though PostgreSQL is running

**Check:**
```bash
gcloud compute firewall-rules list | grep postgres
```

**Verify rule exists:**
```bash
gcloud compute firewall-rules describe allow-postgres-from-web
```

Should allow:
- Source tags: `web-tier`
- Target tags: `db-tier`
- Ports: `5432`

### Issue 4: Wrong Database Credentials

**Check metadata:**
```bash
# On web-server
curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-host -H "Metadata-Flavor: Google"
curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-name -H "Metadata-Flavor: Google"
curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/db-user -H "Metadata-Flavor: Google"
```

**Test connection manually:**
```bash
# From web-server
DB_HOST="<value from above>"
DB_NAME="<value from above>"
DB_USER="<value from above>"

PGPASSWORD='<password>' psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c 'SELECT 1'
```

### Issue 5: Startup Script Failed Partway Through

**Symptom:** No completion marker file

**Check where it failed:**
```bash
# Last lines of startup log
sudo tail -50 /var/log/db-startup.log  # or web-startup.log
```

**Re-run manually:**
```bash
# Make sure you're root
sudo su -

# Re-run the startup script
bash /path/to/startup/script.sh
```

## Using the Diagnostic Script

Run the automated diagnostic script:

```bash
chmod +x ./scripts/diagnose.sh
./scripts/diagnose.sh <PROJECT_ID> <ZONE>
```

This will automatically check:
- VM status
- Service status
- Logs
- Connectivity
- Firewall rules
- Endpoint tests

## GitHub Actions Diagnostics

When tests fail in GitHub Actions, the workflow now automatically collects:
- Serial console output from both VMs
- VM instance status
- Direct curl tests to endpoints

Check the "Collect Diagnostics on Failure" step in the workflow output.

## Force Rebuild

If nothing works, destroy and recreate:

```bash
cd terraform
terraform destroy -auto-approve
sleep 60
terraform apply -auto-approve
```

Then wait 5-7 minutes before testing.
