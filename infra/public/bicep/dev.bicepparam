using './main.bicep'

param location = 'westeurope'
param postgresLocation = 'francecentral'
param namePrefix = 'naasdev01'
param containerImage = 'naasdev01acr.azurecr.io/naas:latest'
param containerCpu = '0.25'
param containerMemory = '0.5Gi'
param minReplicas = 0
param maxReplicas = 1
param deployApplicationGatewayWaf = true
param dbAdministratorPassword = readEnvironmentVariable('DB_ADMIN_PASSWORD', 'REPLACE_ME_DB_ADMIN_PASSWORD')
param jwtSigningKey = readEnvironmentVariable('JWT_SIGNING_KEY', 'REPLACE_ME_JWT_SIGNING_KEY')
