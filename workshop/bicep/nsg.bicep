param userIP string

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'aks-subnet-nsg'
  location: resourceGroup().location
  properties: {
    securityRules: [
      {
        name: 'AllowUserIPTo8080'
        type: 'Microsoft.Network/networkSecurityGroups/securityRules'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: userIP
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
    ]
  }
}

output nsgId string = nsg.id
