# GCloud Commands Cheat Sheet

Quick reference for commonly used `gcloud` commands for managing and troubleshooting the multi-VM application stack.

## 📋 Table of Contents
- [VM Management](#vm-management)
- [SSH and Remote Execution](#ssh-and-remote-execution)
- [Networking and Firewall](#networking-and-firewall)
- [IAM and Service Accounts](#iam-and-service-accounts)
- [Logging and Monitoring](#logging-and-monitoring)
- [API Management](#api-management)
- [Project Configuration](#project-configuration)

---

## VM Management

### List VMs
```bash
# List all VM instances
gcloud compute instances list

# List VMs in specific zone
gcloud compute instances list --filter="zone:us-central1-a"

# List VMs with custom format
gcloud compute instances list \
  --format="table(name,status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"
```

### Describe VM
```bash
# Get detailed info about a VM
gcloud compute instances describe web-server --zone=us-central1-a

# Get specific field (e.g., network tags)
gcloud compute instances describe web-server \
  --zone=us-central1-a \
  --format="get(tags.items)"

# Get internal IP
gcloud compute instances describe db-server \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].networkIP)"
```

### Start/Stop VMs
```bash
# Start a VM
gcloud compute instances start web-server --zone=us-central1-a

# Stop a VM
gcloud compute instances stop web-server --zone=us-central1-a

# Restart a VM
gcloud compute instances stop web-server --zone=us-central1-a
gcloud compute instances start web-server --zone=us-central1-a
```

### Add/Remove Network Tags
```bash
# Add tags to a VM
gcloud compute instances add-tags web-server \
  --tags=web-tier,http-server \
  --zone=us-central1-a

# Remove tags from a VM
gcloud compute instances remove-tags web-server \
  --tags=old-tag \
  --zone=us-central1-a
```

---

## SSH and Remote Execution

### SSH into VMs
```bash
# SSH into web server
gcloud compute ssh web-server --zone=us-central1-a

# SSH into database server
gcloud compute ssh db-server --zone=us-central1-a

# SSH with specific project
gcloud compute ssh web-server \
  --zone=us-central1-a \
  --project=your-project-id
```

### Execute Remote Commands
```bash
# Run a single command
gcloud compute ssh web-server \
  --zone=us-central1-a \
  --command="sudo systemctl status webapp"

# Check service status
gcloud compute ssh web-server \
  --zone=us-central1-a \
  --command="sudo journalctl -u webapp -n 50"

# Check PostgreSQL on database server
gcloud compute ssh db-server \
  --zone=us-central1-a \
  --command="sudo systemctl status postgresql"
```

### View Serial Console Output (Boot Logs)
```bash
# View recent serial console output
gcloud compute instances get-serial-port-output web-server --zone=us-central1-a

# View last 100 lines
gcloud compute instances get-serial-port-output web-server --zone=us-central1-a | tail -100

# View last 200 lines
gcloud compute instances get-serial-port-output web-server \
  --zone=us-central1-a \
  --start=-50000 | tail -200

# Search for specific text in boot logs
gcloud compute instances get-serial-port-output db-server --zone=us-central1-a | grep "startup completed"
```

---

## Networking and Firewall

### List Firewall Rules
```bash
# List all firewall rules
gcloud compute firewall-rules list

# Filter firewall rules
gcloud compute firewall-rules list --filter="name:web-tier"
gcloud compute firewall-rules list --filter="name:postgres"

# Get specific fields
gcloud compute firewall-rules list \
  --format="table(name,sourceRanges,allowed[].map().firewall_rule().list())"
```

### Describe Firewall Rule
```bash
# Get details of a specific firewall rule
gcloud compute firewall-rules describe allow-http-web-tier

# Get source tags
gcloud compute firewall-rules describe allow-postgres-from-web \
  --format="get(sourceTags)"
```

### Create/Update Firewall Rules
```bash
# Create a new firewall rule
gcloud compute firewall-rules create allow-custom-port \
  --network=default \
  --allow=tcp:8080 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=custom-tier

# Update existing firewall rule
gcloud compute firewall-rules update allow-http-web-tier \
  --allow=tcp:80,tcp:443
```

### Networks and Subnets
```bash
# List networks
gcloud compute networks list

# List subnets
gcloud compute networks subnets list

# Describe network
gcloud compute networks describe default
```

### Cloud NAT
```bash
# List Cloud Routers
gcloud compute routers list

# Describe Cloud Router
gcloud compute routers describe nat-router --region=us-central1

# List NAT configurations
gcloud compute routers nats list --router=nat-router --region=us-central1

# Describe NAT configuration
gcloud compute routers nats describe nat-gateway \
  --router=nat-router \
  --region=us-central1
```

---

## IAM and Service Accounts

### List Service Accounts
```bash
# List all service accounts
gcloud iam service-accounts list

# Filter by email
gcloud iam service-accounts list --filter="email:web-tier*"

# Get specific service account
gcloud iam service-accounts describe web-tier-sa@your-project.iam.gserviceaccount.com
```

### IAM Policies
```bash
# Get IAM policy for project
gcloud projects get-iam-policy your-project-id

# Get IAM policy for service account
gcloud iam service-accounts get-iam-policy \
  web-tier-sa@your-project.iam.gserviceaccount.com
```

---

## Logging and Monitoring

### Cloud Logging
```bash
# Read logs for a specific VM
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=web-server-id" \
  --limit=50

# Read logs with timestamp
gcloud logging read "resource.type=gce_instance" \
  --format=json \
  --limit=10

# Filter logs by severity
gcloud logging read "severity>=ERROR" --limit=20

# Tail logs in real-time
gcloud logging tail "resource.type=gce_instance" --format=json
```

### Monitoring
```bash
# List metrics
gcloud monitoring metrics-descriptors list --filter="metric.type:compute"

# Get CPU metrics for a VM
gcloud monitoring time-series list \
  --filter='metric.type="compute.googleapis.com/instance/cpu/utilization"' \
  --format=json
```

---

## API Management

### Enable APIs
```bash
# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Enable IAM API
gcloud services enable iam.googleapis.com

# Enable multiple APIs
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

### List Enabled APIs
```bash
# List all enabled services
gcloud services list

# List enabled services with details
gcloud services list --enabled --format="table(name,title)"

# Check if specific API is enabled
gcloud services list --enabled --filter="name:compute.googleapis.com"
```

---

## Project Configuration

### Project Info
```bash
# Get current project
gcloud config get-value project

# Set default project
gcloud config set project your-project-id

# Get project details
gcloud projects describe your-project-id

# List all projects
gcloud projects list
```

### Configuration
```bash
# Set default zone
gcloud config set compute/zone us-central1-a

# Set default region
gcloud config set compute/region us-central1

# View all configurations
gcloud config list

# Create a new configuration
gcloud config configurations create dev-config

# Switch between configurations
gcloud config configurations activate dev-config
```

---

## 🔧 Common Troubleshooting Commands

### Check VM Status and Connectivity
```bash
# Quick status check
gcloud compute instances list --filter="zone:us-central1-a"

# Get VM external IP
gcloud compute instances describe web-server \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"

# Get VM internal IP
gcloud compute instances describe db-server \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].networkIP)"
```

### Debug Network Issues
```bash
# Check firewall rules affecting a VM
gcloud compute firewall-rules list --filter="targetTags:web-tier"

# Verify VM network tags
gcloud compute instances describe web-server \
  --zone=us-central1-a \
  --format="get(tags.items)"

# Check Cloud NAT configuration
gcloud compute routers nats describe nat-gateway \
  --router=nat-router \
  --region=us-central1
```

### Debug Application Issues
```bash
# Check serial console for startup errors
gcloud compute instances get-serial-port-output web-server --zone=us-central1-a | tail -100

# Execute diagnostic commands remotely
gcloud compute ssh web-server --zone=us-central1-a --command="sudo systemctl status webapp"
gcloud compute ssh db-server --zone=us-central1-a --command="sudo systemctl status postgresql"

# Check application logs
gcloud compute ssh web-server \
  --zone=us-central1-a \
  --command="sudo journalctl -u webapp -n 50 --no-pager"
```

### Complete Diagnostic Script
```bash
#!/bin/bash
PROJECT_ID="your-project-id"
ZONE="us-central1-a"

echo "=== VM Status ==="
gcloud compute instances list --project=$PROJECT_ID --filter="zone:$ZONE"

echo -e "\n=== Firewall Rules ==="
gcloud compute firewall-rules list --project=$PROJECT_ID

echo -e "\n=== Service Accounts ==="
gcloud iam service-accounts list --project=$PROJECT_ID

echo -e "\n=== Web Server Serial Console (last 50 lines) ==="
gcloud compute instances get-serial-port-output web-server --zone=$ZONE --project=$PROJECT_ID | tail -50

echo -e "\n=== Database Server Serial Console (last 50 lines) ==="
gcloud compute instances get-serial-port-output db-server --zone=$ZONE --project=$PROJECT_ID | tail -50
```

---

## 💡 Tips and Best Practices

1. **Use `--format` flag** for custom output formatting (json, yaml, table, etc.)
2. **Use `--filter` flag** to narrow down results instead of piping to grep
3. **Set default project and zone** in config to avoid typing them repeatedly
4. **Use `--dry-run`** when testing destructive commands
5. **Save frequently used commands** as shell aliases or functions
6. **Use `gcloud config configurations`** to manage multiple environments

---

## 📚 Additional Resources

- [Official gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
- [gcloud Compute Reference](https://cloud.google.com/sdk/gcloud/reference/compute)
- [gcloud IAM Reference](https://cloud.google.com/sdk/gcloud/reference/iam)
- [gcloud Logging Reference](https://cloud.google.com/sdk/gcloud/reference/logging)
