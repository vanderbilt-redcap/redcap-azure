targetScope = 'resourceGroup'

@description('The Azure region to target for the deployment. Replaces {loc} in namingConvention.')
param location string = resourceGroup().location

@description('The environment designator for the deployment. Replaces {env} in namingConvention.')
@minLength(1)
param environment string = 'demo'

@description('The workload name. Replaces {workloadName} in namingConvention.')
@minLength(1)
param workloadName string = 'redcap'

@description('The Azure resource naming convention. Include the following placeholders (case-sensitive): {workloadName}, {env}, {rtype}, {loc}, {seq}.')
param namingConvention string = '{workloadName}-{env}-{rtype}-{loc}-{seq}'

@description('A sequence number for the deployment. Used to distinguish multiple deployed versions of the same workload. Replaces {seq} in namingConvention.')
@minValue(1)
@maxValue(99)
param sequence int = 1

@description('A valid Entra ID object ID, which will be assigned RBAC permissions on the deployed resources.')
param identityObjectId string

@description('The address space for the virtual network. Subnets will be carved out. Minimum IPv4 size: /24.')
param vnetAddressSpace string

@description('If available, the public URL to download the REDCap zip file from. Used for debugging purposes. Does not need to be specified when downloading from the REDCap community using a username and password.')
@secure()
param redcapZipUrl string = ''

@description('REDCap Community site username for downloading the REDCap zip file.')
@secure()
param redcapCommunityUsername string

@description('REDCap Community site password for downloading the REDCap zip file.')
@secure()
param redcapCommunityPassword string

@description('The version of REDCap to download from the REDCap Community. This is not used when specifying a ZIP URL.')
param redcapVersion string = ''

@description('Github Repo URL where build scripts are downloaded from')
param scmRepoUrl string = 'https://github.com/microsoft/azure-redcap-paas'

@description('Github Repo Branch where build scripts are downloaded from')
param scmRepoBranch string = 'main'

@description('The command before build to be run on the web app with an elevated privilege. This is used to install the required packages for REDCap operation.')
param prerequisiteCommand string = '/home/startup.sh'

param deploymentTime string = utcNow()

param enableAppServicePrivateEndpoint bool = true

@description('The password to use for the MySQL Flexible Server admin account \'sqladmin\'.')
@secure()
param sqlPassword string

@description('Whether High Availability is enabled for the MySQL Flexible Server. Zone redundant or same zone HA is determined by the value of availabilityZonesEnabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param mySqlHighAvailability string = 'Disabled'

param mySqlSkuName string = 'Standard_B1ms'

@allowed([
  'GeneralPurpose'
  'MemoryOptimized'
  'Burstable'
])
param mySqlSkuTier string = 'Burstable'

@description('The size of the MySQL Flexible Server storage in GB. This cannot be scaled down after server creation.')
param mySqlStorageSizeGB int = 20

param mySqlStorageIops int = 396

@description('The MySQL Flexible Server admin user account name. Defaults to \'sqladmin\'.')
param sqlAdmin string = 'sqladmin'

@description('The outgoing SMTP server FQDN or IP address.')
param smtpFQDN string = ''

@description('The outgoing SMTP server port.')
param smtpPort string = ''

@description('The email address to use as the sender for outgoing emails.')
param smtpFromEmailAddress string = ''

param appServiceSkuName string = 'B2'

@description('Determines whether availability zone redundancy is enabled for the MySQL Flexible Server and the app service. The region must support availability zones.')
param availabilityZonesEnabled bool = false

@description('Optional: Resource Group ID that contains existing Private DNS zones. If empty, Private DNS zones are created in the current resource group.')
param existingPrivateDnsZonesResourceGroupId string = ''

@description('Optional: Resource ID of an existing Virtual Network. If provided, the deployment will not create a new VNet.')
param existingVirtualNetworkId string = ''

param appServiceTimeZone string = 'UTC'

@description('Enable Azure Front Door instead of SSH VM jumpbox for secure access.')
param enableFrontDoor bool = true

// If deploying into an existing VNet, provide existing subnet names inside the `subnets` object.
param subnets object = {
  PrivateLinkSubnet: {
    addressPrefix: cidrSubnet(vnetAddressSpace, 27, 0)
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          location
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          location
        ]
      }
    ]
  }
  IntegrationSubnet: {
    // Two /27 have already been created, which add up to a /26. This the second /26 (index = 1).
    addressPrefix: cidrSubnet(vnetAddressSpace, 26, 1)
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          location
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          location
        ]
      }
      {
        service: 'Microsoft.Web'
        locations: [
          location
        ]
      }
    ]
    delegation: 'Microsoft.Web/serverFarms'
  }
  MySQLFlexSubnet: {
    // Two /26 have been allocated; that's equivalent to sixteen /29s.
    addressPrefix: cidrSubnet(vnetAddressSpace, 29, 16)
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          location
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          location
        ]
      }
    ]
    delegation: 'Microsoft.DBforMySQL/flexibleServers'
  }
}

var sequenceFormatted = format('{0:00}', sequence)
var deploymentNameStructure = '${workloadName}-${environment}-${sequenceFormatted}-{rtype}-${deploymentTime}'

var tags = {
  workload: workloadName
  environment: environment
}

var resourceTypes = [
  'vnet'
  'st'
  'app'
  'kv'
  'mysql'
  'plan'
  'uami'
  'dplscr'
  'law'
]

@batchSize(1)
module nameModule 'modules/common/createValidAzResourceName.bicep' = [
  for workload in resourceTypes: {
    name: 'nameGen-${workload}-${uniqueString(deploymentNameStructure, workload)}'
    scope: subscription()
    params: {
      location: location
      environment: environment
      namingConvention: namingConvention
      resourceType: workload
      sequence: sequence
      workloadName: workloadName
      addRandomChars: 4
    }
  }
]

module rolesModule 'modules/common/roles.bicep' = {
  name: 'roles-${uniqueString(deploymentNameStructure)}'
  scope: subscription()
}

var vnetName = empty(existingVirtualNetworkId)
  ? nameModule[0].outputs.shortName
  : split(existingVirtualNetworkId, '/')[8]

var strgName = nameModule[1].outputs.shortName
var webAppName = nameModule[2].outputs.shortName
var kvName = nameModule[3].outputs.shortName
var sqlName = nameModule[4].outputs.shortName
var planName = nameModule[5].outputs.shortName
var uamiName = nameModule[6].outputs.shortName
var dplscrName = nameModule[7].outputs.shortName
var lawName = nameModule[8].outputs.shortName

var appInsightsName = 'appInsights-${webAppName}'

module virtualNetwork 'modules/networking/vnet.bicep' = if (empty(existingVirtualNetworkId)) {
  name: 'vnet-${uniqueString(deploymentNameStructure)}'
  params: {
    virtualNetworkName: vnetName
    vnetAddressPrefix: vnetAddressSpace
    location: location
    subnets: subnets
    customDnsIPs: []
    tags: tags
  }
}

var createdSubnets = empty(existingVirtualNetworkId)
  ? any(reduce(virtualNetwork!.outputs.subnets, {}, (cur, next) => union(cur, next)))
  : {}

var virtualNetworkId = empty(existingVirtualNetworkId)
  ? virtualNetwork!.outputs.virtualNetworkId
  : existingVirtualNetworkId

var privateEndpointSubnetId = empty(existingVirtualNetworkId)
  ? createdSubnets.PrivateLinkSubnet.id
  : '${existingVirtualNetworkId}/subnets/${subnets.PrivateLinkSubnet.existingSubnetName}'

var integrationSubnetId = empty(existingVirtualNetworkId)
  ? createdSubnets.IntegrationSubnet.id
  : '${existingVirtualNetworkId}/subnets/${subnets.IntegrationSubnet.existingSubnetName}'

var mySqlSubnetId = empty(existingVirtualNetworkId)
  ? createdSubnets.MySQLFlexSubnet.id
  : '${existingVirtualNetworkId}/subnets/${subnets.MySQLFlexSubnet.existingSubnetName}'

module uamiModule 'modules/uami/main.bicep' = {
  name: 'uami-${uniqueString(deploymentNameStructure)}'
  params: {
    tags: tags
    location: location
    uamiName: uamiName
  }
}

module logAnalyticsWorkspace 'modules/monitoring/law.bicep' = {
  name: 'law-${uniqueString(deploymentNameStructure)}'
  params: {
    logAnalyticsWorkspaceName: lawName
    logAnalyticsWorkspaceSku: 'PerGB2018'
    retentionInDays: 30
    location: location
    tags: union(tags, {
      workloadType: 'monitoring'
    })
  }
}

module appInsights 'modules/monitoring/appInsights.bicep' = {
  name: 'appi-${uniqueString(deploymentNameStructure)}'
  params: {
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
    location: location
    tags: union(tags, {
      workloadType: 'monitoring'
    })
  }
}

// Key Vault + KV DNS
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
module keyVaultPrivateDnsModule 'modules/pdns/main.bicep' = if (empty(existingPrivateDnsZonesResourceGroupId)) {
  name: 'kv-dns-${uniqueString(deploymentNameStructure)}'
  params: {
    privateDnsZoneName: keyVaultPrivateDnsZoneName
    virtualNetworkId: virtualNetworkId
    tags: tags
  }
}

var keyVaultPrivateDnsZoneId = empty(existingPrivateDnsZonesResourceGroupId)
  ? keyVaultPrivateDnsModule!.outputs.privateDnsId
  : '${existingPrivateDnsZonesResourceGroupId}/providers/Microsoft.Network/privateDnsZones/${keyVaultPrivateDnsZoneName}'

// MySQL needs the UAMI principalId to set parameters via deployment script.
module mySqlPrivateDnsModule 'modules/pdns/main.bicep' = if (empty(existingPrivateDnsZonesResourceGroupId)) {
  name: 'mysql-dns-${uniqueString(deploymentNameStructure)}'
  params: {
    privateDnsZoneName: 'privatelink.mysql.database.azure.com'
    virtualNetworkId: virtualNetworkId
    tags: tags
  }
}

var mySqlPrivateDnsZoneId = empty(existingPrivateDnsZonesResourceGroupId)
  ? mySqlPrivateDnsModule!.outputs.privateDnsId
  : '${existingPrivateDnsZonesResourceGroupId}/providers/Microsoft.Network/privateDnsZones/privatelink.mysql.database.azure.com'

// Storage DNS
var storagePrivateDnsZoneName = 'privatelink.blob.${az.environment().suffixes.storage}'
module storagePrivateDnsModule 'modules/pdns/main.bicep' = if (empty(existingPrivateDnsZonesResourceGroupId)) {
  name: 'st-dns-${uniqueString(deploymentNameStructure)}'
  params: {
    privateDnsZoneName: storagePrivateDnsZoneName
    virtualNetworkId: virtualNetworkId
    tags: tags
  }
}

var storagePrivateDnsZoneId = empty(existingPrivateDnsZonesResourceGroupId)
  ? storagePrivateDnsModule!.outputs.privateDnsId
  : '${existingPrivateDnsZonesResourceGroupId}/providers/Microsoft.Network/privateDnsZones/${storagePrivateDnsZoneName}'

// MySQL
module mySqlModule 'modules/sql/sql.bicep' = {
  name: 'mysql-${uniqueString(deploymentNameStructure)}'
  params: {
    flexibleSqlServerName: sqlName
    location: location
    tags: union(tags, {
      workloadType: 'mySqlFlexibleServer'
    })

    skuName: mySqlSkuName
    SkuTier: mySqlSkuTier
    StorageSizeGB: mySqlStorageSizeGB
    StorageIops: mySqlStorageIops

    peSubnetId: mySqlSubnetId
    privateDnsZoneId: mySqlPrivateDnsZoneId

    adminUserName: sqlAdmin
    adminPassword: sqlPassword
    mysqlVersion: '8.0.21'

    databaseName: 'redcapdb'

    highAvailability: (mySqlHighAvailability == 'Enabled')
    availabilityZonesEnabled: availabilityZonesEnabled

    roles: rolesModule.outputs.roles

    uamiId: uamiModule.outputs.id
    uamiPrincipalId: uamiModule.outputs.principalId

    deploymentScriptName: dplscrName

    // Required charset and collation for REDCap
    database_charset: 'utf8'
    database_collation: 'utf8_general_ci'
  }
}

var secrets = {
  sqlAdminName: mySqlModule.outputs.sqlAdmin
  sqlPassword: sqlPassword
  redcapCommunityUsername: redcapCommunityUsername
  redcapCommunityPassword: redcapCommunityPassword
}

module keyVaultModule 'modules/kv/kv.bicep' = {
  name: 'kv-${uniqueString(deploymentNameStructure)}'
  params: {
    keyVaultName: kvName
    location: location
    tags: union(tags, {
      workloadType: 'keyVault'
    })
    peSubnetId: privateEndpointSubnetId
    privateDnsZoneId: keyVaultPrivateDnsZoneId
    secrets: secrets
    roleAssignments: [
      {
        RoleDefinitionId: rolesModule.outputs.roles['Key Vault Administrator']
        objectId: identityObjectId
      }
      {
        RoleDefinitionId: rolesModule.outputs.roles['Key Vault Secrets User']
        objectId: uamiModule.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
    deploymentNameStructure: deploymentNameStructure
  }
}

var storageAccountKeySecretName = 'storageKey'
var defaultSecretNames = map(items(secrets), s => s.key)
var additionalSecretNames = [storageAccountKeySecretName]
var secretNames = concat(defaultSecretNames, additionalSecretNames)

module kvSecretReferencesModule 'modules/common/appSvcKeyVaultRefs.bicep' = {
  name: 'kv-refs-${uniqueString(deploymentNameStructure)}'
  scope: subscription()
  params: {
    keyVaultName: kvName
    secretNames: secretNames
  }
}

module storageAccountModule 'modules/storage/storage.bicep' = {
  name: 'st-${uniqueString(deploymentNameStructure)}'
  params: {
    location: location
    tags: union(tags, {
      workloadType: 'storageAccount'
    })
    storageAccountName: strgName
    peSubnetId: privateEndpointSubnetId
    storageContainerName: 'redcap'
    kind: 'StorageV2'
    storageAccountSku: 'Standard_LRS'

    privateDnsZoneId: storagePrivateDnsZoneId

    keyVaultId: keyVaultModule.outputs.id
    keyVaultSecretName: storageAccountKeySecretName

    deploymentNameStructure: deploymentNameStructure
  }
}

module webAppModule 'modules/webapp/main.bicep' = {
  name: 'app-${uniqueString(deploymentNameStructure)}'
  params: {
    webAppName: webAppName
    appServicePlanName: planName
    location: location
    skuName: appServiceSkuName
    peSubnetId: privateEndpointSubnetId

    appInsights_connectionString: appInsights.outputs.appInsightsConnectionString
    appInsights_instrumentationKey: appInsights.outputs.appInsightsInstrumentationKey

    linuxFxVersion: 'php|8.2'
    tags: tags
    customTags: {
      workloadType: 'webApp'
    }

    existingPrivateDnsZonesResourceGroupId: existingPrivateDnsZonesResourceGroupId
    privateDnsZoneName: 'privatelink.azurewebsites.net'
    virtualNetworkId: virtualNetworkId

    redcapZipUrl: redcapZipUrl
    dbHostName: mySqlModule.outputs.fqdn
    dbName: mySqlModule.outputs.databaseName

    dbUserNameSecretRef: kvSecretReferencesModule.outputs.keyVaultRefs[2]
    dbPasswordSecretRef: kvSecretReferencesModule.outputs.keyVaultRefs[3]

    redcapCommunityUsernameSecretRef: kvSecretReferencesModule.outputs.keyVaultRefs[1]
    redcapCommunityPasswordSecretRef: kvSecretReferencesModule.outputs.keyVaultRefs[0]
    redcapVersion: redcapVersion

    storageAccountKeySecretRef: kvSecretReferencesModule.outputs.keyVaultRefs[4]
    storageAccountContainerName: storageAccountModule.outputs.containerName
    storageAccountName: storageAccountModule.outputs.name

    integrationSubnetId: integrationSubnetId

    scmRepoUrl: scmRepoUrl
    scmRepoBranch: scmRepoBranch
    prerequisiteCommand: prerequisiteCommand

    smtpFQDN: smtpFQDN
    smtpFromEmailAddress: smtpFromEmailAddress
    smtpPort: smtpPort

    deploymentNameStructure: deploymentNameStructure

    uamiId: uamiModule.outputs.id

    availabilityZonesEnabled: availabilityZonesEnabled
    enablePrivateEndpoint: enableAppServicePrivateEndpoint

    timeZone: appServiceTimeZone
  }
}

module sshVm 'modules/frontdoor/main.bicep' = if (enableFrontDoor) {
  name: 'fd-${uniqueString(deploymentNameStructure)}'
  params: {
    frontDoorName: '${workloadName}-${environment}-${sequenceFormatted}-fd'
    location: 'global'
    webAppHostname: webAppModule.outputs.webAppHostname
    tags: union(tags, {
      workloadType: 'frontDoor'
    })
  }
}

output webAppUrl string = webAppModule.outputs.webAppUrl
output frontDoorUrl string = enableFrontDoor ? sshVm!.outputs.frontDoorUrl : ''
