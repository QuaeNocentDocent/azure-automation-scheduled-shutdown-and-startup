param(
  # Parameter help description
  [Parameter(Mandatory=$true)]
  [string] $AutomationAccountName,
  [Parameter(Mandatory=$true)]
  [string] $ResourceGroupname
)

Login-AzureRmAccount
Get-AzureRmSubscription | Out-GridView -OutputMode single | Select-AzureRmSubscription

$parameters=@{
  omsAutomationAccountName=$AutomationAccountName
}

New-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupname -TemplateParameterObject $parameters -TemplateFile .\azuredeploy.json

