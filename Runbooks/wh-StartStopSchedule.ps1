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
$context= convertfrom-json $WebhookData.RequestBody

#check for mandatory params
if($context.action -notin @('set','remove') -or `
  [String]::IsNullOrEmpty($context.parameters.subscriptionName) -or `
  [String]::IsNullOrEmpty($context.parameters.resourceGroupName)) {
    throw ('Required parameters are missing: {0}' -f $context)
  }

switch ($context.action) {
  'set'{
    $command='.\Set-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptioName -resourceGroupName -$context.parameters.resourceGroupName -vmName $context.parameters.vmName'
    if(![String]::IsNullOrEmpty($context.parameters.schedule)) {$command+=' -schedule $context.parameters.schedule'}
    if(![String]::IsNullOrEmpty($context.parameters.tagName)) {$command+=' -tagName $context.parameters.tagName'}
    if(![String]::IsNullOrEmpty($context.parameters.enableTagName)) {$command+=' -enableTagName $context.parameters.enableTagName'}
    if(![String]::IsNullOrEmpty($context.parameters.enabled)) {$command+=' -enabled $context.parameters.enabled'}    
    if(![String]::IsNullOrEmpty($context.parameters.connectionName)) {$command+=' -connectionName $context.parameters.connectionName'}        
  }
  'remove' {
    $command='.\Remove-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptioName -resourceGroupName -$context.parameters.resourceGroupName -vmName $context.parameters.vmName'
    if(![String]::IsNullOrEmpty($context.parameters.tagName)) {$command+=' -tagName $context.parameters.tagName'}
    if(![String]::IsNullOrEmpty($context.parameters.connectionName)) {$command+=' -connectionName $context.parameters.connectionName'}            
  }
}
write-output ('About to execute {0}' -f $command)
invoke-expression $command

