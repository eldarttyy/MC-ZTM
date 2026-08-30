# MC-ZTM — multi-cloud zero-trust landing zone

Terraform that stands up the same network security posture in AWS, Azure and GCP
from one root module. The point is not that it deploys three clouds; it is that a
**new site inherits the architecture on day one** instead of being hardened
afterwards by whoever remembers to.

```
terraform/
  main.tf                     root module; CIDR-overlap assertions, per-cloud toggles
  modules/aws_network/        VPC, public/private tiers, workload SG, flow logs
  modules/azure_network/      VNet, per-subnet NSGs, flow logs
  modules/gcp_network/        VPC, explicit deny backstops, VPC flow logs
  modules/entra_identity/     Entra ID groups, app roles, workload federation
scripts/Audit-EntraUsers.ps1  dormant-account audit
```

## What is enforced, not documented

* **Default deny in every direction, stated explicitly.** The AWS default security
  group is emptied; Azure carries a `Deny-Internet-Inbound` rule per subnet
  *"so the intent is visible in the portal"*; GCP gets lowest-priority
  `deny-all-ingress` and `deny-all-egress` backstops *"so nothing rides in on an
  implicit rule."* Implicit denies are correct and invisible; explicit ones get
  reviewed.
* **East-west is allow-listed.** Workload security groups permit intra-VPC ingress
  and HTTPS egress only. Lateral movement is a policy decision, not a leftover.
* **No static credentials anywhere.** Workload identity per cloud — IAM role,
  managed identity, service account — federated to Entra ID, which owns identity
  once rather than being replicated three times.
* **No public administrative path.** Administrative access is via SSM Session
  Manager (AWS) and IAP (GCP); `admin_cidrs` is a break-glass allow-list and
  `0.0.0.0/0` is rejected by variable validation, not by convention.
* **Flow logs on by default**, with configurable retention, in all three clouds —
  because segmentation you cannot observe is segmentation you cannot verify.
* **Non-overlapping ranges are asserted, not assumed.** Terraform has no CIDR
  overlap function, so the root module reduces each range to integer bounds and
  fails the plan on collision. That assertion is what keeps future peering, VPN
  attachment and Cloud WAN viable instead of discovering a conflict at migration.

## Use

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set admin_cidrs, tenant, subscription
terraform init
terraform plan
```

Each cloud is independently toggleable (`enable_aws`, `enable_azure`,
`enable_gcp`) so one landing zone can be stood up and torn down at a time inside
free-tier limits. State is local by default so the repo plans with no setup; the
remote-backend block with locking is written out in `providers.tf` for anything
shared.
