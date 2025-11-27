output "web_server_name" {
  description = "Name of the web tier VM instance"
  value       = google_compute_instance.web_server.name
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "zone" {
  description = "GCP Zone"
  value       = var.zone
}

output "web_server_ip" {
  description = "External IP address of the web server"
  value       = google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip
}

output "web_server_external_ip" {
  description = "External IP address of the web server (alias)"
  value       = google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip
}

output "web_server_internal_ip" {
  description = "Internal IP address of the web server"
  value       = google_compute_instance.web_server.network_interface[0].network_ip
}

output "web_server_url" {
  description = "URL to access the web application"
  value       = "http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}"
}

output "api_health_endpoint" {
  description = "API health check endpoint"
  value       = "http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}/api/health"
}

output "api_db_status_endpoint" {
  description = "API database status endpoint"
  value       = "http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}/api/db-status"
}

output "db_server_name" {
  description = "Name of the database tier VM instance"
  value       = google_compute_instance.db_server.name
}

output "db_server_internal_ip" {
  description = "Internal IP address of the database server"
  value       = google_compute_instance.db_server.network_interface[0].network_ip
}

output "web_tier_sa_email" {
  description = "Email of the web tier service account"
  value       = google_service_account.web_tier_sa.email
}

output "db_tier_sa_email" {
  description = "Email of the database tier service account"
  value       = google_service_account.db_tier_sa.email
}

output "ssh_web_command" {
  description = "Command to SSH into the web tier VM"
  value       = "gcloud compute ssh ${google_compute_instance.web_server.name} --zone=${var.zone} --project=${var.project_id}"
}

output "ssh_db_command" {
  description = "Command to SSH into the database tier VM"
  value       = "gcloud compute ssh ${google_compute_instance.db_server.name} --zone=${var.zone} --project=${var.project_id}"
}

output "test_commands" {
  description = "Commands to test the application"
  value = <<-EOT
    # Test health endpoint
    curl http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}/api/health
    
    # Test database status
    curl http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}/api/db-status
    
    # Test users API
    curl http://${google_compute_instance.web_server.network_interface[0].access_config[0].nat_ip}/api/users
  EOT
}
