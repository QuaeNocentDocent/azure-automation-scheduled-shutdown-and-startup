[cmdletBinding()]
Param
(
  [Parameter(Mandatory=$true)]
  [string]$SubscriptionName,
  [Parameter(Mandatory=$false)]
  $ConnectionName='AzureRunAsConnection',
  [Parameter(Mandatory=$true)]
  [string] $vmName,
  [Parameter(Mandatory=$true)]
  [string] $resourceGroupName,
  [string] $shutdownScript
)

# Credit: s_lapointe  https://gallery.technet.microsoft.com/scriptcenter/Easily-obtain-AccessToken-3ba6e593
function Get-AzureRmCachedAccessToken()
{
  $ErrorActionPreference = 'Stop'
   
  if(-not (Get-Module AzureRm.Profile)) {
    Import-Module AzureRm.Profile
  }
  $azureRmProfileModuleVersion = (Get-Module AzureRm.Profile).Version
  # refactoring performed in AzureRm.Profile v3.0 or later
  if($azureRmProfileModuleVersion.Major -ge 3) {
    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azureRmProfile.Accounts.Count) {
      Write-Error "Ensure you have logged in before calling this function."   
    }
  } else {
    # AzureRm.Profile &lt; v3.0
    $azureRmProfile = [Microsoft.WindowsAzure.Commands.Common.AzureRmProfileProvider]::Instance.Profile
    if(-not $azureRmProfile.Context.Account.Count) {
      Write-Error "Ensure you have logged in before calling this function."   
    }
  }
   
  $currentAzureContext = Get-AzureRmContext
  $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
  Write-Debug ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
  $token = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)
  $token.AccessToken
}

function Delete-Extension()
{
  param(
    [String] $SubscriptionID,
    [String] $ResourceGroupName,
    [String] $VMName,
    [String] $ExtensionName,
    [String] $APIVersion,
    [String] $token
  )

  Write-Verbose 'Delete Extension'
  $Uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}/extensions/{3}?api-version={4}' -f `
    $SubscriptionID, $Resourcegroupname, $VMName, $ExtensionName, $APIVersion
  $params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers     = @{
      'authorization' = "Bearer $token"
    }
    Method      = 'DELETE'
    URI         = $Uri
  }
  $StatusInfo = Invoke-RestMethod @params -UseBasicParsing
  return $StatusInfo
}

function Get-ScriptStatus()
{
  param(
    [String] $SubscriptionID,
    [String] $ResourceGroupName,
    [String] $VMName,
    [String] $ExtensionName,
    [String] $APIVersion,
    [String] $token
  )

  Write-Verbose 'Get Extension message info'
  $Uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}/extensions/{3}?$expand=instanceView&api-version={4}' `
    -f $SubscriptionID, $Resourcegroupname, $VMName, $ExtensionName, $APIVersion
  $params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers     = @{
      'authorization' = "Bearer $token"
    }
    Method      = 'Get'
    URI         = $Uri
  }
  $StatusInfo = Invoke-RestMethod @params
  return $StatusInfo
}


function Run-Script()
{
  param(
    [String] $SubscriptionID,
    [String] $ResourceGroupName,
    [String] $VMName,
    [String] $ExtensionName,
    [String] $APIVersion,
    [String] $token,
    [String] $scriptPayload
  )

  $Uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}/extensions/{3}?api-version={4}' -f `
    $SubscriptionID, $Resourcegroupname, $VMName, $ExtensionName, $APIVersion
  
  $params = @{
    ContentType = 'application/json'
    Headers     = @{
      'authorization' = "Bearer $token"
    }
    Method      = 'PUT'
    URI         = $Uri
    Body        = $scriptPayload
  }
  
  $InitialConfig = Invoke-RestMethod @params
  return $InitialConfig

}


  <#
    Get-AzureRmVmImagePublisher -Location WestEurope | `
    Get-AzureRmVMExtensionImageType | `
    Get-AzureRmVMExtensionImage | Select Type, PublisherName, Version | ft -autosize
  #>

  <# STandard powersdhell methods are synchronous this is not something we want for a shutdown script, after a given timeout we must go on with the shutdown
    $ExtensionType = 'CustomScriptExtension'
    $Publisher = 'Microsoft.Compute'
    $Version = '1.9'
    $settings=@{
        fileUri=''
        commandToExecute='powershell.exe -File c:\temp\test.ps1'
    }
    $result=Set-AzureRmVMExtension -Publisher $publisher -ExtensionType $ExtensionType -Settings $settings -VMName preAzuresdk1 -ResourceGroupName preAzureSdk1 -ForceRerun 'TestPS' -Name TestPS -Location westeurope -TypeHandlerVersion $version
    $extendedResult=Get-AzureRmVMExtension -ResourceGroupName preazuresdk1 -VMName preazuresdk1 -Name TestPS
    $result=Remove-AzurermVMExtension -ResourceGroupName preAzureSDK1 -VMName preAzureSDK1 –Name TestPS -Force -Verbose -Debug
  #>

  $error.clear()
	try
	{
		# Get the connection "AzureRunAsConnection "
		$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

		Add-AzureRmAccount `
			-ServicePrincipal `
			-TenantId $servicePrincipalConnection.TenantId `
			-ApplicationId $servicePrincipalConnection.ApplicationId `
			-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
	}
	catch
	{
		if (!$servicePrincipalConnection)
		{
			$ErrorMessage = "Connection $connectionName not found."
			throw $ErrorMessage
		}
		else
		{
			Write-Error -Message $_.Exception
			throw $_.Exception
		}
	}

	$subscription = Select-AzureRmSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue -ErrorVariable subErr
	if($subErr -or !$subscription) {
    if ($subErr) {throw $subErr.tostring()}
    else {throw 'Error getting subscription'}
	}

  # Test Params
<#  
  $resourceGroupName='preAzureSdk1'
  $vmName='preAzureSdk1'
  $subScriptionName= 'Azure Benefits'
  $shutdownScript=@"
    {
      "run": "powershell.exe -ExecutionPolicy Unrestricted -file c:\\temp\\test.ps1",
      "timeout": 60
    }
"@
#>

  
  $APIVersion = '2017-03-30'
  $token = Get-AzureRmCachedAccessToken
  $ExtensionName='QNDStopScript'
  $SubscriptionID = (Get-AzureRmContext).Subscription.Id
  $scriptHash = ConvertFrom-Json -InputObject $shutdownScript
  #need to escape \ in json
  $scriptHash.run=$scriptHash.run.Replace('\','\\')
  $vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName  
  $location = $vm.Location
  if($vm.StorageProfile.OsDisk.OsType -ieq 'Windows') {
    $Publisher='Microsoft.Compute'
    $Type='CustomScriptExtension'
    $Version='1.9'
    $Settings="{""fileUris"" : '',""commandToExecute"": ""$($scriptHash.run)""}"
  }
  else {
    $Publisher = 'Microsoft.OSTCExtensions'
    $Type = 'CustomScriptForLinux'
    $Version = '1.5'
    $settings="{""commandToExecute""=""$($scriptHash.run)""}"
  }


  $scriptPayload=@"
  {
    "location": "$location",
    "properties": {
      "publisher":  "$Publisher",
      "type": "$Type",
      "typeHandlerVersion": $Version",
      "autoUpgradeMinorVersion": true,
      "forceUpdateTag": "$ExtensionName",
      "settings": $Settings
    }
  }
"@



$timer=get-date
$kickoff=Run-Script -SubscriptionID $SubscriptionID -ResourceGroupName $resourceGroupName -VMName $vmName -ExtensionName $ExtensionName -APIVersion $APIVersion -token $token -scriptPayload $scriptPayload
do {
  start-sleep -Seconds 15
  $status = Get-ScriptStatus -SubscriptionID $SubscriptionID -ResourceGroupName $resourceGroupName -VMName $vmName -ExtensionName $ExtensionName -APIVersion $APIVersion -token $token  
} while ($status.properties.provisioningState -ne 'Succeeded' -and (((get-date) - $timer).TotalSeconds -le $scriptHash.timeout))

  #multiple delete-extension statements in the following code are used because I don't know yet which is the best strategy in case of error. Remove it or not?
  if ($status.properties.provisioningState -ne 'Succeeded') {
    if ((get-date) - $timer.TotalSeconds -gt $scriptHash.timeout) {
      #in case of timeout we don't remove the script since it is still running, is this correct? If we do this the next time the VM is started the script run again. It's a tough call
      write-output 'Timeoue executing shutdown script'
      Delete-Extension -SubscriptionID $SubscriptionID -ResourceGroupName $resourceGroupName -VMName $vmName -ExtensionName $ExtensionName -APIVersion $APIVersion -token $token  
    }
    else {
      Delete-Extension -SubscriptionID $SubscriptionID -ResourceGroupName $resourceGroupName -VMName $vmName -ExtensionName $ExtensionName -APIVersion $APIVersion -token $token  
    }
  }
  else {
    Delete-Extension -SubscriptionID $SubscriptionID -ResourceGroupName $resourceGroupName -VMName $vmName -ExtensionName $ExtensionName -APIVersion $APIVersion -token $token    
  }
  #for now just retrun the last status we got
  return $status
  






