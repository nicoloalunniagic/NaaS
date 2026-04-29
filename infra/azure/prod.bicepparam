using './main.bicep'

param location = 'westeurope'
param namePrefix = 'naasprod01'
param containerImage = 'naasprod01acr.azurecr.io/naas:latest'
param containerCpu = '0.5'
param containerMemory = '1.0Gi'
param minReplicas = 2
param maxReplicas = 5
param dbAdministratorPassword = readEnvironmentVariable('DB_ADMIN_PASSWORD', '')
