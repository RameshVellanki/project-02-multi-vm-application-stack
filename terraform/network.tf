# Firewall Rule: Allow HTTP traffic to web tier
resource "google_compute_firewall" "web_tier_http" {
  name    = "allow-http-web-tier"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [var.http_port]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-tier"]

  description = "Allow HTTP traffic to web tier from internet"

  depends_on = [google_project_service.compute]
}

# Firewall Rule: Allow PostgreSQL traffic from web tier to database tier
resource "google_compute_firewall" "db_tier_postgres" {
  name    = "allow-postgres-from-web"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [var.db_port]
  }

  source_tags = ["web-tier"]
  target_tags = ["db-tier"]

  description = "Allow PostgreSQL traffic from web tier to database tier"

  depends_on = [google_project_service.compute]
}

# Firewall Rule: Allow internal communication between tiers
resource "google_compute_firewall" "internal_communication" {
  name    = "allow-internal-tier-communication"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  depends_on = [google_project_service.compute]

  source_tags = ["web-tier", "db-tier"]
  target_tags = ["web-tier", "db-tier"]

  description = "Allow internal communication between application tiers"
}
