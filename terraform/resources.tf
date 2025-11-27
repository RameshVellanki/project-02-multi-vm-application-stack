# Service Account for Web Tier
resource "google_service_account" "web_tier_sa" {
  account_id   = "${var.web_vm_name}-sa"
  display_name = "Service Account for Web Tier"
  description  = "Custom service account for web tier VM with minimal permissions"

  depends_on = [google_project_service.iam]
}

# IAM: Web Tier Logging
resource "google_project_iam_member" "web_tier_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.web_tier_sa.email}"
}

# IAM: Web Tier Monitoring
resource "google_project_iam_member" "web_tier_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.web_tier_sa.email}"
}

# Service Account for Database Tier
resource "google_service_account" "db_tier_sa" {
  account_id   = "${var.db_vm_name}-sa"
  display_name = "Service Account for Database Tier"
  description  = "Custom service account for database tier VM with minimal permissions"

  depends_on = [google_project_service.iam]
}

# IAM: Database Tier Logging
resource "google_project_iam_member" "db_tier_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.db_tier_sa.email}"
}

# IAM: Database Tier Monitoring
resource "google_project_iam_member" "db_tier_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.db_tier_sa.email}"
}

# Database Tier VM Instance
resource "google_compute_instance" "db_server" {
  name         = var.db_vm_name
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["db-tier"]
  labels = var.labels

  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    network = "default"
    # No external IP - database is private
  }

  service_account {
    email  = google_service_account.db_tier_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "FALSE"
    db-name        = var.db_name
    db-user        = var.db_user
    db-password    = var.db_password
  }

  metadata_startup_script = file("${path.module}/../scripts/db-tier-startup.sh")

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  allow_stopping_for_update = true

  depends_on = [
    google_project_service.compute,
    google_service_account.db_tier_sa,
    google_project_iam_member.db_tier_logging,
    google_project_iam_member.db_tier_monitoring,
    google_compute_router_nat.nat_gateway  # Ensure NAT is ready for package downloads
  ]
}

# Web Tier VM Instance
resource "google_compute_instance" "web_server" {
  name         = var.web_vm_name
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["web-tier", "http-server"]
  labels = var.labels

  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    network = "default"
    
    # External IP for internet access
    access_config {
      # Ephemeral IP
    }
  }

  service_account {
    email  = google_service_account.web_tier_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "FALSE"
    db-host        = google_compute_instance.db_server.network_interface[0].network_ip
    db-port        = var.db_port
    db-name        = var.db_name
    db-user        = var.db_user
    db-password    = var.db_password
    app-port       = var.app_port
  }

  metadata_startup_script = file("${path.module}/../scripts/web-tier-startup.sh")

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  allow_stopping_for_update = true

  depends_on = [
    google_project_service.compute,
    google_compute_instance.db_server,
    google_service_account.web_tier_sa,
    google_project_iam_member.web_tier_logging,
    google_project_iam_member.web_tier_monitoring,
    google_compute_firewall.web_tier_http,
    google_compute_firewall.db_tier_postgres
  ]
}
