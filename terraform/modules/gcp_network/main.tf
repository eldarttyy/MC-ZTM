/**
 * GCP network landing zone.
 *
 * Zero-trust posture:
 *   - Custom-mode VPC (auto subnet creation off) so no unmanaged /20s appear in
 *     20 regions the moment the network is created.
 *   - SSH is reachable only from the Identity-Aware Proxy range, so every shell
 *     session is brokered by Google identity instead of an open port 22.
 *   - Explicit lowest-priority deny for ingress and egress; only HTTPS egress
 *     and intra-VPC traffic sit above it.
 *   - Private Google Access on both subnets removes the need for a Cloud NAT.
 */

locals {
  name = "${var.name_prefix}-gcp"

  # Source range used by IAP TCP forwarding. Fixed and documented by Google.
  iap_range = "35.235.240.0/20"
}

resource "google_compute_network" "this" {
  name                            = local.name
  description                     = "MC-ZTM landing zone VPC"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "public" {
  name                     = "${local.name}-public"
  ip_cidr_range            = var.public_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "private" {
  name                     = "${local.name}-private"
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  name        = "${local.name}-allow-internal"
  description = "East-west traffic inside the landing zone"
  network     = google_compute_network.this.name
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [var.vpc_cidr]

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
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${local.name}-allow-iap-ssh"
  description = "SSH via Identity-Aware Proxy only; no public 22 anywhere"
  network     = google_compute_network.this.name
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [local.iap_range]
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_admin_https" {
  count = length(var.admin_cidrs) > 0 ? 1 : 0

  name        = "${local.name}-allow-admin-https"
  description = "Break-glass HTTPS from approved administrative networks"
  network     = google_compute_network.this.name
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = var.admin_cidrs
  target_tags   = ["admin-https"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${local.name}-deny-all-ingress"
  description = "Backstop deny so nothing rides in on an implicit rule"
  network     = google_compute_network.this.name
  direction   = "INGRESS"
  priority    = 65000

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_https_egress" {
  name        = "${local.name}-allow-https-egress"
  description = "Outbound HTTPS to Google APIs and package mirrors"
  network     = google_compute_network.this.name
  direction   = "EGRESS"
  priority    = 1000

  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "deny_all_egress" {
  name        = "${local.name}-deny-all-egress"
  description = "GCP allows all egress by default; this closes it"
  network     = google_compute_network.this.name
  direction   = "EGRESS"
  priority    = 65000

  destination_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

resource "google_service_account" "workload" {
  account_id   = "${substr(replace(local.name, "_", "-"), 0, 24)}-wl"
  display_name = "MC-ZTM workload service account"
  description  = "Attached to landing-zone compute; telemetry write access only"
}

resource "google_project_iam_member" "workload" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workload.email}"
}
