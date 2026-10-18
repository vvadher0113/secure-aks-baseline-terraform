# Architecture and Design Decisions

## Network Topology

```
Internet
    |
    v
Azure Firewall (Standard, zone-redundant)
    |
Hub VNet  10.0.0.0/22
  ├── AzureFirewallSubnet          10.0.0.0/26   Azure Firewall
  ├── AzureFirewallMgmtSubnet      10.0.0.64/26  reserved — forced-tunnel scenarios only
  ├── AzureBastionSubnet           10.0.0.128/26  Azure Bastion (Standard)
  └── GatewaySubnet                10.0.0.192/27  reserved — VPN/ExpressRoute (not deployed)
    |  (VNet peering, bidirectional)
    |
Spoke VNet  10.1.0.0/20
  ├── snet-aks-system              10.1.0.0/24   AKS system node pool
  ├── snet-aks-user                10.1.4.0/22   AKS user node pool
  └── snet-private-endpoints       10.1.8.0/24   ACR and Key Vault private endpoints

AKS Pod CIDR     10.244.0.0/16  (Azure CNI Overlay — not routed in VNet)
AKS Service CIDR 172.16.0.0/16  (Kubernetes VIPs — not routed outside cluster)
CoreDNS IP       172.16.0.10
```

## Address Plan

| Prefix | Subnet / Use | Size | Sizing rationale |
|--------|-------------|------|-----------------|
| 10.0.0.0/22 | Hub VNet | 1024 IPs | Fits all hub connectivity subnets in a single small block; hub never hosts workloads |
| 10.0.0.0/26 | AzureFirewallSubnet | 64 IPs | Azure requires exactly /26 for the firewall data-plane NIC |
| 10.0.0.64/26 | AzureFirewallManagementSubnet | 64 IPs | Reserved for forced-tunnel scenarios (not deployed); same /26 requirement as firewall subnet |
| 10.0.0.128/26 | AzureBastionSubnet | 64 IPs | Minimum is /27; /26 gives headroom for Standard Bastion scale units |
| 10.0.0.192/27 | GatewaySubnet | 32 IPs | Azure minimum is /27 for VPN/ER gateways; reserved but not deployed |
| 10.1.0.0/20 | Spoke VNet | 4096 IPs | Sized to hold all current subnets plus room to add future workload subnets without VNet resize |
| 10.1.0.0/24 | snet-aks-system | 256 IPs | With CNI Overlay each node uses 1 VNet IP (not 1 per pod); fixed 3-node system pool needs < 10 |
| 10.1.4.0/22 | snet-aks-user | 1024 IPs | Supports large autoscaling pool; /22 allows rolling upgrades (surge nodes) without exhaustion |
| 10.1.8.0/24 | snet-private-endpoints | 256 IPs | Holds current PEs (ACR, Key Vault) with room for additional private endpoints as the platform grows |
| 10.244.0.0/16 | Pod CIDR (CNI Overlay) | 65 536 IPs | Not routed in VNet; pods allocate from this range invisibly to Azure networking; verify no overlap with on-premises 10.x before deploying |
| 172.16.0.0/16 | Service CIDR | 65 536 IPs | Kubernetes service VIPs never leave the cluster; 172.16.x.x is unused in most enterprise networks |
| 172.16.0.10 | CoreDNS service IP | n/a | First usable address in the service CIDR after the network address |

## Key Design Decisions

### Azure CNI Overlay with pod CIDR outside VNet

Azure CNI Overlay decouples pod IP allocation from the VNet address space.
Pods receive IPs from `10.244.0.0/16` (configurable), which does not overlap
the hub or spoke VNet ranges. Because pod IPs are never routed in the VNet,
this baseline uses a standard Kubernetes default (`10.244.0.0/16`) rather
than an RFC1918-private range that might conflict with on-premises address
space. Validate there is no conflict before deploying into an environment with
existing 10.244.x.x assignments. This allows large pod densities without
consuming VNet address space, and removes the constraint of pre-sizing subnets
for max pods per node.

### UDR Egress via Azure Firewall

AKS is configured with `outbound_type = "userDefinedRouting"`. Route tables
on both AKS subnets send all traffic (0.0.0.0/0) to the firewall's private IP.
The firewall enforces allow-listed AKS egress FQDNs (using the
`AzureKubernetesService` FQDN tag), MCR, and Azure Monitor. All other egress
is denied by default.

Benefits: egress inspection, consistent audit trail, no public outbound IPs
on nodes.

### Separate System and User Node Pools

The system pool uses `only_critical_addons_enabled = true` plus a
`CriticalAddonsOnly=true:NoSchedule` taint. Application pods land only on
the user pool. This prevents workload resource pressure from evicting
system components (CoreDNS, CNI, metrics-server).

### Azure Linux (Mariner) OS

AzureLinux is Microsoft's minimal container-optimized Linux distribution.
It has a smaller attack surface than Ubuntu, receives rapid CVE patches from
Microsoft, and is the default for new AKS deployments.

### Private Cluster

The AKS API server has no public endpoint. Access requires:
- Direct connectivity to the spoke VNet (ExpressRoute, VPN, or peering), or
- Azure Bastion + jump box inside the hub, or
- `az aks command invoke` for one-off commands from a CI/CD runner with
  ARM API access.

Stage 2 (cluster-config) must run from inside the VNet or via a self-hosted
GitHub Actions runner in the spoke VNet.

### Local Accounts Disabled

All cluster access flows through Entra ID. No static kubeconfig credentials
exist. Operators use `az aks get-credentials` and authenticate interactively
or via Workload Identity in automation.

### Two Resource Groups

Hub and spoke resources live in separate resource groups. This maps to the
separation between platform connectivity (owned by a network team) and
application infrastructure (owned by a platform/AKS team). It also limits
blast radius: deleting the spoke RG cannot accidentally destroy the firewall.

### KEDA via Managed Add-on

KEDA is enabled through the AKS `workload_auto_scaler_profile`. Using the
managed add-on keeps KEDA version aligned with the AKS version, avoids
Helm management overhead, and is covered by Microsoft support.

## HIPAA/HITRUST Safeguard Alignment

> **Important — alignment is not certification.** The controls described
> below are designed to be *aligned with* HIPAA Security Rule safeguards and
> HITRUST CSF requirements. This codebase has not been independently audited
> or certified. Organizations subject to HIPAA must conduct their own risk
> analysis, gap assessment, and obtain formal certification through a qualified
> third-party assessor.

| HIPAA Safeguard | Implementation | Code Location |
|-----------------|---------------|---------------|
| Access control (AC) | Local accounts disabled, Entra ID RBAC | `aks.tf` `disable_local_accounts` |
| Audit logging | Container Insights, Defender for Containers, Firewall Insights | `aks.tf`, `firewall.tf` |
| Data encryption in transit | HTTPS enforced, TLS 1.2 minimum on all services | `keyvault.tf`, `acr.tf` |
| Data encryption at rest | Host encryption on node pools | `aks.tf` `enable_host_encryption` |
| Network segmentation | Hub-spoke, NSGs on all subnets, deny-all default | `networking.tf`, `firewall.tf` |
| Least privilege | Specific RBAC roles (AcrPull, KV Secrets User) | `rbac.tf` |
| Key management | Key Vault with purge protection, RBAC auth, private endpoint | `keyvault.tf` |
| Vulnerability management | Defender for Containers, Azure Policy add-on | `aks.tf` |
| Private endpoints | ACR and Key Vault behind private endpoints, no public access | `acr.tf`, `keyvault.tf` |
| Secret management | Key Vault CSI driver with auto-rotation | `aks.tf` |
| Workload isolation | System/user node pool separation, pod security contexts | `aks.tf`, `gitops/` |

## Additional Controls to Evaluate for Your Environment

The following areas are intentionally out of scope for this baseline but are
commonly required for production healthcare workloads:

- **Customer-managed keys** for AKS node disk encryption and Key Vault
- **Azure Firewall Premium** with IDPS and TLS inspection
- **Diagnostic settings** for all resources to Log Analytics
- **Azure Monitor alerts** for compliance events
- **Pod Security Admission** (PSA) policies
- **Network Policy** enforcement beyond Calico defaults
- **Backup and DR** for persistent volumes
