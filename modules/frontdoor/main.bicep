param location string = 'global'
param frontDoorName string
param webAppHostname string
param tags object = {}

// Create a simple Azure Front Door with CDN caching and optional WAF
// Note: WAF is managed separately; here we create the CDN profile
resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: frontDoorName
  location: location
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  tags: tags
  properties: {
    originResponseTimeoutSeconds: 30
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoor
  name: 'origin-group'
  properties: {
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: 50
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probeIntervalInSeconds: 100
      probeProtocol: 'Https'
      probeRequestType: 'HEAD'
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin (Web App)
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'webapp-origin'
  properties: {
    hostName: webAppHostname
    originHostHeader: webAppHostname
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Endpoint
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoor
  name: '${take(frontDoorName, 50)}-endpoint'
  location: location
  properties: {
    enabledState: 'Enabled'
  }
}

// Route
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'api-route'
  dependsOn: [
    origin
  ]
  properties: {
    customDomains: []
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
}

output frontDoorUrl string = 'https://${endpoint.properties.hostName}'
output frontDoorId string = frontDoor.id
output endpointHostname string = endpoint.properties.hostName
output profileName string = frontDoor.name

