variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}
variable "compartment_id" {}
variable "cluster_name" {
  default = "k8s"
}
variable "kubernetes_version" {
  default = "v1.30.1" # Check for the latest supported version
}
variable "node_pool_name" {
  default = "k8s-node-pool"
}
variable "node_pool_node_shape" {
  default = "VM.Standard.A1.Flex"
}
variable "node_pool_node_count" {
  default = 3
}

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

resource "oci_core_vcn" "k8s_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_id
  display_name   = "k8s-vcn"
}

resource "oci_core_internet_gateway" "k8s_ig" {
  compartment_id = var.compartment_id
  display_name   = "k8s-internet-gateway"
  vcn_id         = oci_core_vcn.k8s_vcn.id
}

resource "oci_core_route_table" "k8s_route_table" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.k8s_ig.id
  }
}

resource "oci_core_security_list" "k8s_security_list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-security-list"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }

  ingress_security_rules {
    protocol = "6" // TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_subnet" "k8s_subnet" {
  cidr_block        = "10.0.1.0/24"
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.k8s_vcn.id
  display_name      = "k8s-subnet"
  route_table_id    = oci_core_route_table.k8s_route_table.id
  security_list_ids = [oci_core_security_list.k8s_security_list.id]
}

resource "oci_core_subnet" "k8s_node_subnet" {
  cidr_block        = "10.0.9.0/24"
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.k8s_vcn.id
  display_name      = "k8s-node-subnet"
  route_table_id    = oci_core_route_table.k8s_route_table.id
  security_list_ids = [oci_core_security_list.k8s_security_list.id]
}

data "oci_containerengine_cluster_option" "k8s_cluster_option" {
  cluster_option_id = "all"
}

locals {
  latest_k8s_version = data.oci_containerengine_cluster_option.k8s_cluster_option.kubernetes_versions[length(data.oci_containerengine_cluster_option.k8s_cluster_option.kubernetes_versions) - 1]
  default_ad         = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_id
  kubernetes_version = local.latest_k8s_version
  name               = "k8s-cluster"
  vcn_id             = oci_core_vcn.k8s_vcn.id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.k8s_subnet.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.k8s_subnet.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }
}

data "oci_core_images" "oracle_linux_image" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_id
  kubernetes_version = local.latest_k8s_version
  name               = "k8s-node-pool"
  node_config_details {
    node_pool_pod_network_option_details {
      cni_type = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids = [oci_core_subnet.k8s_subnet.id]
    }

    placement_configs {
      availability_domain = local.default_ad
      subnet_id           = oci_core_subnet.k8s_node_subnet.id

      preemptible_node_config {
        preemption_action {
          type                    = "TERMINATE"
          is_preserve_boot_volume = false
        }
      }
    }
    size = 3
  }
  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 16
    ocpus         = 8
  }

  node_source_details {
    image_id    = data.oci_core_images.oracle_linux_image.images[0].id
    source_type = "image"
  }

  initial_node_labels {
    key   = "name"
    value = "k8s-cluster"
  }
}

// data "oci_containerengine_addon_options" "available_addons" {
//   kubernetes_version = local.latest_k8s_version
// }

// # Add this output to display the available addons
// output "available_addons" {
//   value = [for addon in data.oci_containerengine_addon_options.available_addons.addon_options : addon.name]
// }
