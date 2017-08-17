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
    if(![String]::IsNullOrEmpty($context.parameters.scriptTagName)) {$OptionalParameters.Add('ScriptTagName', $context.parameters.scriptTagName)}      
    if(![String]::IsNullOrEmpty($context.parameters.script)) {$OptionalParameters.Add('shutdownScript', ($context.parameters.script | convertto-json))}              
    .\Set-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptionName -resourceGroupName $context.parameters.resourceGroupName `
      -vmName $context.parameters.vmName -schedule ($context.parameters.schedule | convertto-json -Depth 4) @OptionalParameters
  }
  'remove' {
    if(![String]::IsNullOrEmpty($context.parameters.tagName)) {$OptionalParameters.Add('tagNames', [array]$context.parameters.tagNames)}
    if(![String]::IsNullOrEmpty($context.parameters.connectionName)) {$OptionalParameters.Add('connectionName', $context.parameters.connectionName)}          
    .\Remove-VMStartStopSchedule.ps1 -subscriptionName $context.parameters.subscriptionName -resourceGroupName $context.parameters.resourceGroupName `
      -vmName $context.parameters.vmName
  }
}

$body=@"
{"parameters":{"enableTagName":"EnableStartStopSchedule","enabled":true,"resourceGroupName":"GollumOnDocker","schedule":
{"5":{"S":"8","E":"20"},"1":{"S":"8","E":"20"},"2":{"S":"8","E":"20"},"6":{"S":"0","E":"0"},"4":{"S":"8","E":"20"},"3":{
"S":"8","E":"20"},"0":{"S":"0","E":"0"},"TzId":"Central European Standard 
Time"},"connectionName":"","subscriptionName":"Azure Benefits","script":{"run":"sh /tmp/test.sh","timeOut":"60"},"vmName
":"GollumD","tagName":"StartStopSchedule","scriptTagName":"ScriptStartStopSchedule"},"action":"set"}
"@