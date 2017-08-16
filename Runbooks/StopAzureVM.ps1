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
	$script = convertfrom-json $shutdownScript
	if($subErr -or !$subscription) {
    if ($subErr) {throw $subErr.tostring()}
    else {throw 'Error getting subscription'}
	}
	if(! [String]::IsNullOrEmpty($script)) {
		#check to see if it is linux or windows
		$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
		#http://www.gi-architects.co.uk/2016/07/custom-script-extension-for-arm-vms-in-azure/
		if($vm.StorageProfile.OsDisk.OsType -ieq 'Windows') {
			#the script is synchronous so we must possibly rise the stop timeout, the script is always invoked as powershell  
			# $result=set-AzureRmVMCustomScriptExtension -ResourceGroupName preAzureSDK1 -VMName preAzureSDK1 -Run $script.run' -Name TestPS -FileUri @('c:\temp\test.ps1') -Location westeurope -ForceRerun "go"
			# get-AzureRmVMCustomScriptExtension -ResourceGroupName preAzureSDK1 -VMName preAzureSDK1 -Name TestPS
			#must IF NOT THE SCRIPT IS EXECUTED AGAIN WHEN THE VM STARTS
			#Remove-AzurermVMCustomScriptExtension -ResourceGroupName preAzureSDK1 -VMName preAzureSDK1 –Name TestPS -Force
		}
		else {
			#$ExtensionType = ‘CustomScriptForLinux’
			#$Publisher = ‘Microsoft.OSTCExtensions’
			#$Version = ‘1.5’
			#$settings=@{
    		#	commandToExecute='sh /tmp/test.sh'
			#}
			#$result=Set-AzureRmVMExtension -Publisher $publisher -ExtensionType $ExtensionType -Settings $settings -VMName GollumD -ResourceGroupName GollumOnDocker -ForceRerun "go" -Name TestSH -Location westeurope -TypeHandlerVersion $version
			# Get-AzureRmVMExtension -VMName GollumD -ResourceGroupName GollumOnDocker -Name TestSH
			#must IF NOT THE SCRIPT IS EXECUTED AGAIN WHEN THE VM STARTS
			#Remove-AzurermVMCustomScriptExtension -ResourceGroupName preAzureSDK1 -VMName preAzureSDK1 –Name TestPS -Force			
		}
	
	}
    Stop-AzureRMVM -Name $vmName -ResourceGroupName $resourceGroupName -Force

    if ($error) {throw ('Error stopping {0}. {1}' -f $vmName, $error[0])}