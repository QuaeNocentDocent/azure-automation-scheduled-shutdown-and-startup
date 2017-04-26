#this is the webhook entry point for the Set/Remove powershell scripts
[CmdletBinding()]
param(
  [object] $WebhookData
)

if(! $WebhookData) {
  throw 'This runbook can only be invoked through webhooks'
}

<#
  .WebhookName
  .RequestHeader
  .RequestBody

  we use .requestBody with a json payload in the following from
  {
    "action": "set/remove"
    "parameters": {
      "subscriptioName": "",
      "resourceGroupName": "",
      "vmName": "",
      "schedule": "",
      "tagName": "",
      "enableTagName": "",
      "enabled": "",
      "connectionName": ""
    }

  }
#>
write-verbose $WebhookData.RequestBody
$context= convertfrom-json $WebhookData.RequestBody

#check for mandatory params
if(@('set','remove') -notcontains $context.action -or `
  [String]::IsNullOrEmpty($context.parameters.subscriptionName) -or `
  [String]::IsNullOrEmpty($context.parameters.resourceGroupName)) {
    throw ('Required parameters are missing: {0}' -f $context)
  }

$OptionalParameters = New-Object -TypeName Hashtable

switch ($context.action) {
  'set'{
    if(![String]::IsNullOrEmpty($context.parameters.tagName)) {$OptionalParameters.Add('tagName', $context.parameters.tagName)}
    if(![String]::IsNullOrEmpty($context.parameters.enableTagName)) {$OptionalParameters.Add('enableTagName', $context.parameters.enableTagName)}
    if(![String]::IsNullOrEmpty($context.parameters.enabled)) {$OptionalParameters.Add('enabled', $context.parameters.enabled)}    
    if(![String]::IsNullOrEmpty($context.parameters.connectionName)) {$OptionalParameters.Add('connectionName', $context.parameters.connectionName)}      
    .\Set-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptionName -resourceGroupName $context.parameters.resourceGroupName `
      -vmName $context.parameters.vmName -schedule $context.parameters.schedule @OptionalParameters
  }
  'remove' {
    if(![String]::IsNullOrEmpty($context.parameters.tagName)) {$OptionalParameters.Add('tagName', $context.parameters.tagName)}
    if(![String]::IsNullOrEmpty($context.parameters.connectionName)) {$OptionalParameters.Add('connectionName', $context.parameters.connectionName)}          
    .\Remove-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptionName -resourceGroupName $context.parameters.resourceGroupName `
      -vmName $context.parameters.vmName -schedule $context.parameters.schedule @OptionalParameters
  }
}

