targetScope = 'subscription'

@description('The resource group name to deploy everything into.')
param resourceGroupName string = 'Redcap'

@description('The Azure region to target for the deployment. Replaces {loc} in namingConvention.')
param location string = 'westus2'

@description('The environment designator for the deployment. Replaces {env} in namingConvention.')
// @allowed([
//   'test'
//   'demo'
//   'prod'
// ])
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
param existingPrivateDnsZonesResourceGroupId string = ''
param existingVirtualNetworkId string = ''

param appServiceTimeZone string = 'UTC'

// Azure Front Door configuration
param enableFrontDoor bool = true

var sequenceFormatted = format('{0:00}', sequence)
var deploymentNameStructure = '${workloadName}-${environment}-${sequenceFormatted}-{rtype}-${deploymentTime}'

// TODO: Define type
param subnets object = {
  // TODO: Define securityRules
  // TODO: Add existingSubnetName property for existing subnet
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
    // TODO: /29 seems very small
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

var tags = {
  workload: workloadName
  environment: environment
}

resource redcapResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: union(tags, {
    workloadType: 'redcap'
  })
}

module redcap 'main.rg.bicep' = {
  name: 'redcap-${uniqueString(deploymentNameStructure)}'
  scope: redcapResourceGroup
  params: {
    location: location
    environment: environment
    workloadName: workloadName
    namingConvention: namingConvention
    sequence: sequence
    identityObjectId: identityObjectId
    vnetAddressSpace: vnetAddressSpace
    redcapZipUrl: redcapZipUrl
    redcapCommunityUsername: redcapCommunityUsername
    redcapCommunityPassword: redcapCommunityPassword
    redcapVersion: redcapVersion
    scmRepoUrl: scmRepoUrl
    scmRepoBranch: scmRepoBranch
    prerequisiteCommand: prerequisiteCommand
    enableAppServicePrivateEndpoint: enableAppServicePrivateEndpoint
    sqlPassword: sqlPassword
    mySqlHighAvailability: mySqlHighAvailability
    mySqlSkuName: mySqlSkuName
    mySqlSkuTier: mySqlSkuTier
    mySqlStorageSizeGB: mySqlStorageSizeGB
    mySqlStorageIops: mySqlStorageIops
    sqlAdmin: sqlAdmin
    smtpFQDN: smtpFQDN
    smtpPort: smtpPort
    smtpFromEmailAddress: smtpFromEmailAddress
    appServiceSkuName: appServiceSkuName
    availabilityZonesEnabled: availabilityZonesEnabled
    existingPrivateDnsZonesResourceGroupId: existingPrivateDnsZonesResourceGroupId
    existingVirtualNetworkId: existingVirtualNetworkId
    appServiceTimeZone: appServiceTimeZone
    subnets: subnets

    enableFrontDoor: enableFrontDoor
  }
}

output webAppUrl string = redcap.outputs.webAppUrl
output frontDoorUrl string = redcap.outputs.frontDoorUrl
