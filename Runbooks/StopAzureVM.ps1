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
	if($subErr -or !$subscription) {
    if ($subErr) {throw $subErr.tostring()}
    else {throw 'Error getting subscription'}
	}
	if(! [String]::IsNullOrEmpty($shutdownScript)) {
    $result = Run-VMScriptAsync -SubscriptionName $SubscriptionName -ConnectionName $ConnectionName -VMName $vmName -ResourceGroupName $resourceGroupName -ShutdownScript $shutdownScript
    if ($result.properties.provisioningState -ine 'Succeeded') {write-warning 'Error executing shutdown script, proceeding anyway'}
	}
  Stop-AzureRMVM -Name $vmName -ResourceGroupName $resourceGroupName -Force

    if ($error) {throw ('Error stopping {0}. {1}' -f $vmName, $error[0])}