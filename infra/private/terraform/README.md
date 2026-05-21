# Private Terraform — No-as-a-Service

This configuration mirrors the private (hub-and-spoke VNet) Bicep topology.
For a full description of the network design, provisioned resources, and
deployment steps see [infra/private/bicep/README.md](../bicep/README.md).

Terraform requires `>= 1.8.0` and the `hashicorp/azurerm ~> 4.0` provider.

## Backend configuration

State is stored remotely. Provide a backend config at `init` time:

```bash
terraform init \
  -backend-config="resource_group_name=<rg>" \
  -backend-config="storage_account_name=<sa>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=private.terraform.tfstate"
```

## Known differences from Bicep

### Key Vault secret seeding (known limitation)

Bicep uses ARM's trusted-service network bypass to write secrets into the
private Key Vault at deployment time. Terraform runs from a GitHub-hosted
runner that cannot reach the Key Vault data plane when
`public_network_access_enabled = false`.

**Consequence:** `azurerm_key_vault_secret` resources are intentionally
absent. The Container App `secret` blocks use direct `value` fields instead
of Key Vault references. The KV RBAC assignments are still created so that
secrets can be seeded manually after the runner is done:

```bash
az keyvault secret set --vault-name <name> \
  --name database-connection-string --value "<connection-string>"
az keyvault secret set --vault-name <name> \
  --name jwt-signing-key --value "<key>"
```

The container will fail to start until both secrets are present in the vault.

### Application Insights / AMPLS

Controlled by the `deploy_app_insights` variable (default `true`). Set to
`false` to skip Application Insights, the Azure Monitor Private Link Scope,
and its private endpoint — useful for cost-constrained environments.

```bash
terraform apply -var="deploy_app_insights=false" ...
```
