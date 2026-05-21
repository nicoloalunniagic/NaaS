# Public Terraform — No-as-a-Service

This configuration mirrors the public Bicep topology. For a full description
of the provisioned resources, networking, and deployment steps see
[infra/public/bicep/README.md](../bicep/README.md).

Terraform requires `>= 1.8.0` and the `hashicorp/azurerm ~> 4.0` provider.

## Backend configuration

State is stored remotely. Provide a backend config at `init` time:

```bash
terraform init \
  -backend-config="resource_group_name=<rg>" \
  -backend-config="storage_account_name=<sa>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=public.terraform.tfstate"
```

The storage account must have `shared_access_key_enabled = false`; use
`storage_use_azuread = true` in the provider block (already set) so the
provider authenticates with the deploying principal's Azure AD identity.

## Known differences from Bicep

| Area | Bicep | Terraform |
|---|---|---|
| Log Analytics Workspace | Created inside `main.bicep`; ID passed to `foundation.bicep` which wires it to the Container App Environment | LAW always created (`azurerm_log_analytics_workspace.law`); also wired to the CAE directly |
| Application Insights | Deployed when `deployAppInsights = true` (default) | Deployed only when `app_insights_workspace_resource_id` is set (non-null); omitted by default |
| Storage shared-key auth | `allowSharedKeyAccess: false` | `shared_access_key_enabled = false`; provider sets `storage_use_azuread = true` to avoid 403 on post-create data-plane polling |
