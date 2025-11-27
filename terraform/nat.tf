# Cloud Router for Cloud NAT
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  region  = var.region
  network = "default"

  depends_on = [google_project_service.compute]
}

# Cloud NAT for private instances to access internet
resource "google_compute_router_nat" "nat_gateway" {
  name   = "nat-gateway"
  router = google_compute_router.nat_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [google_compute_router.nat_router]
}
