param name string
param location string
param tags object = {}
param subnetId string
param backendFqdn string

@description('Allowed source CIDRs for /docs and /openapi/v1.json access. Empty array blocks docs for everyone.')
param docsAllowedCidrs array = []

@description('Enable IP restriction on /docs and /openapi/v1.json paths.')
param restrictDocsByIp bool = false

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${name}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: '${name}-waf'
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: true
      fileUploadLimitInMb: 100
      maxRequestBodySizeInKb: 128
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
    customRules: [
      {
        name: 'block-sqli-signatures'
        priority: 10
        ruleType: 'MatchRule'
        action: 'Block'
        state: 'Enabled'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'QueryString'
              }
              {
                variableName: 'RequestUri'
              }
            ]
            operator: 'Contains'
            negationConditon: false
            matchValues: [
              ' or 1=1'
              'union select'
              'pg_sleep('
              'information_schema'
            ]
            transforms: [
              'Lowercase'
              'UrlDecode'
            ]
          }
        ]
      }
      {
        name: 'block-xss-signatures'
        priority: 20
        ruleType: 'MatchRule'
        action: 'Block'
        state: 'Enabled'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'QueryString'
              }
              {
                variableName: 'RequestUri'
              }
            ]
            operator: 'Contains'
            negationConditon: false
            matchValues: [
              '<script'
              'onerror='
              'onload='
              'javascript:'
            ]
            transforms: [
              'Lowercase'
              'UrlDecode'
            ]
          }
        ]
      }
      {
        name: 'block-docs-from-non-allowlist'
        priority: 30
        ruleType: 'MatchRule'
        action: 'Block'
        state: restrictDocsByIp ? 'Enabled' : 'Disabled'
        matchConditions: concat(
          [
            {
              matchVariables: [
                {
                  variableName: 'RequestUri'
                }
              ]
              operator: 'Regex'
              negationCondition: false
              matchValues: [
                '^/(docs|openapi/v1\\.json)(/.*)?$'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ],
          empty(docsAllowedCidrs)
            ? []
            : [
                {
                  matchVariables: [
                    {
                      variableName: 'RemoteAddr'
                    }
                  ]
                  operator: 'IPMatch'
                  negationCondition: true
                  matchValues: docsAllowedCidrs
                  transforms: []
                }
              ]
        )
      }
      {
        name: 'global-rate-limit'
        priority: 40
        ruleType: 'RateLimitRule'
        action: 'Block'
        state: 'Enabled'
        rateLimitDuration: 'OneMin'
        rateLimitThreshold: 300
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RequestUri'
              }
            ]
            operator: 'Contains'
            negationConditon: false
            matchValues: [
              '/'
            ]
            transforms: []
          }
        ]
      }
    ]
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 3
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'httpPort'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'apiBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: backendFqdn
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'apiHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          requestTimeout: 30
          pickHostNameFromBackendAddress: false
          hostName: backendFqdn
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', name, 'apiProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', name, 'appGatewayFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', name, 'httpPort')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'apiRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', name, 'httpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', name, 'apiBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', name, 'apiHttpSettings')
          }
          rewriteRuleSet: {
            id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', name, 'securityHeaderRewrite')
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: 'securityHeaderRewrite'
        properties: {
          rewriteRules: [
            {
              name: 'removeServerHeader'
              ruleSequence: 10
              conditions: []
              actionSet: {
                responseHeaderConfigurations: [
                  {
                    headerName: 'Server'
                    headerValue: ''
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'apiProbe'
        properties: {
          protocol: 'Https'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          host: backendFqdn
          pickHostNameFromBackendHttpSettings: false
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
  }
}

output name string = appGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
output url string = 'http://${publicIp.properties.ipAddress}'
