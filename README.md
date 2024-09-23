# oke-terraform

Deploy ARM-based Oracle Cloud Kubernetes Cluster with Terraform

## Guide

1. Install [oci-cli](https://github.com/oracle/oci-cli)
2. Run `once setup config,` and find acid on the Oracle cloud console.
3. Create `terraform.tfvars` with the below config:

```env
# Define the region
region = "ap-tokyo-1"

# Define the tenancy OCID
tenancy_ocid = "ocid1.tenancy.oc1.."

# Define the user OCID
user_ocid = "ocid1.user.oc1.."

# Define the compartment OCID
compartment_id = "ocid1.tenancy.oc1.."

# Define the fingerprint of the API key
fingerprint = "33:bc:49.."

# Define the path to the private key, e.g. /Users/mayo/.oci/oci_api_key.pem
private_key_path = ""
```

4. `terraform init`, `terraform plan` and `terraform apply` then boom, I have a low-cost K8s cluster now.
