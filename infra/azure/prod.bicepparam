using './main.bicep'

param location = 'westeurope'
param namePrefix = 'noaasprod01'
param containerImage = 'noaasprod01acr.azurecr.io/noaas:latest'
param containerCpu = '0.5'
param containerMemory = '1.0Gi'
param minReplicas = 2
param maxReplicas = 5
param deployAppInsights = true
