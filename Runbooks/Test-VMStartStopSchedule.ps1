#workflow Test-VMStartStopSchedule
#{
    <#
	.SYNOPSIS
		Lists every VM on every resource group of a subscription and test for a Schedule tag existance and takes an action to start or shutdown the VM depending on scheduled hours.
	.DESCRIPTION
		Lists every VM on every resource group of a subscription and test for a Schedule tag existance and takes an action to start or shutdown the VM depending on scheduled hours.
	.PARAMETER SubscriptioName
		Name of Azure subscription where resource groups and resources are located to be evaluated.
	.EXAMPLE
		How to manually execute this runbook from a Powershell command prompt:
		
        Add-AzureRmAccount
        
        Select-AzureRmSubscription -SubscriptionName pmcglobal
        
		$params = @{"SubscriptioName"="pmcglobal"}
		Start-AzureRmAutomationRunbook -Name "Test-ResourceSchedule" -Parameters $params -AutomationAccountName "pmcAutomation01" -ResourceGroupName "rgAutomation"

	.NOTE
        In order to make this runbook run in a scheduled manner, a bootstrap runbook per subscription must be created, like Start-ResourceScheduleTest. 
    
		Since this runbook is being created from Azure Portal (azure.portal.com), this is Resource Manager so the following cmdlets
		should be executed when starting it from an Azure Powershell 1.0 command prompt:
		
		Add-AzureRmAccount
		Select-AzureRmSubscription -SubscriptionName <subscritpionname>
		
	.DISCLAIMER
		This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
	    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
	    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
	    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object
	    code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software
	    product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the
	    Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims
	    or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
	    Please note: None of the conditions outlined in the disclaimer above will supersede the terms and conditions contained
	    within the Premier Customer Services Description.
	#>
	[cmdletBinding()]
	Param
	(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionName,
		[Parameter(Mandatory=$false)]
		$TagName='StartStopSchedule',
		[Parameter(Mandatory=$false)]
		$EnableTagName='EnableStartStopSchedule',
		[Parameter(Mandatory=$false)]
		$ConnectionName='AzureRunAsConnection'
		
	)
    
	function GetSchedule
	{
		param
		(
			[Parameter(Mandatory=$false)]
			[System.Collections.Hashtable]$tags,
            [string] $TagName,
            [string] $EnableTagName
		)
		
		if ($tags -eq $null)
		{
			return $null
		}

		$schedule=$tags[$TagName]        
		$enabled=[bool] $tags[$EnableTagName]
		if ($enabled) {return [string]$schedule}
		else {
			write-output 'Schedule is disabled, skipping'
			return $null
		}
	}

	# Getting Azure PS Version
	$azPsVer = Get-Module -ListAvailable -Name Azure
	Write-Output "Azure PS Version $($azPsVer.Version.ToString())"

	$azRmPsVer = Get-Module -ListAvailable -Name AzureRm.Compute
	Write-Output "Azure RM PS Version AzureRm.Compute $($azRmPsVer.Version.ToString())"

	# Authenticating and setting up current subscription
	Write-Output "Authenticating"

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

	Write-Output "Getting list of resource groups"
	
	$rgs = Get-AzureRmResourceGroup
	
	Write-Output " Resource group count: $($rgs.count)"

	$vmList = @()
	
	# Building Schedule List for VMs that contains the Schedule Tag
	Write-Output "Building Schedule List for VMs that contains the Schedule Tag"
	foreach ($rg in $rgs)
	{
		Write-Output "Getting VMs from Resource Group $($rg.ResourceGroupName)"
		$vms = Find-AzureRmResource -ResourceGroupNameContains $rg.ResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines"
		
		foreach ($vm in $vms)
		{
			Write-Output "VM to be evaluated: $($vm.name)"

			if ($vm.Tags.Keys -icontains $TagName)
			{
				write-verbose 'Schedule present on VM'
				$scheduleInfo = GetSchedule -tags $vm.Tags -TagName $tagName -EnableTagName $EnableTagName
				if ($scheduleInfo) {
					Write-Output "   Resource Schedule for vm $($vm.name) is $scheduleInfo"
					$vmObj = New-Object -TypeName PSObject -Property @{"Name"=$vm.Name;"ResourceGroupName"=$vm.ResourceGroupName;"Schedule"=$scheduleInfo}
					$vmList += $vmObj
				}
			}
			else
			{
				if ($rg.tags.Keys -icontains $TagName)
				{
					write-verbose 'Schedule present on RG'
					$scheduleInfo = GetSchedule -tags $rg.Tags -TagName $tagName -EnableTagName $EnableTagName
					if($scheduleInfo) {
						Write-Output ('   Resource Group Schedule for vm {0} is {1}' -f $vm.name, ($scheduleInfo))
						$vmObj = New-Object -TypeName PSObject -Property @{"Name"=$vm.Name;"ResourceGroupName"=$vm.ResourceGroupName;"Schedule"=$scheduleInfo}
						$vmList += $vmObj
					}
				}
			}
		}
	}

	write-Output "vmList Count => $($vmList.Count)"

	$vmsToStop = @()
	$vmsToStart = @()

	# Evaluating which VM will start and which will shutdown
	Write-Output "Evaluating which VM will start and which will shutdown"
	foreach ($vm in $vmList)
	{
		#I don't wnat to abort the entire process is a single VM has an invalid schedule
		try {
			Write-Output "   Evaluating vm $($vm.name)"
			Write-Output "   Getting Schedule"

			$schedule = ConvertFrom-Json $vm.Schedule 

			if ($schedule.psobject.Properties["TzId"] -ne $null)
			{
				$resourceTz = [System.TimeZoneInfo]::FindSystemTimeZoneById($schedule.TzId)
				$utcCurrentTime = [datetime]::UtcNow
				$resourceTzCurrentTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcCurrentTime,$resourceTz)

				if ($schedule.psobject.Properties[$resourceTzCurrentTime.DayOfWeek.value__] -ne $null)
				{
					if ($schedule.($resourceTzCurrentTime.DayOfWeek.value__).PSObject.Properties["S"] -ne $null)
					{
						try
						{
							$startTime = [int]::Parse($schedule.($resourceTzCurrentTime.DayOfWeek.value__).S)
						}
						catch
						{
							throw "Invalid Startup Time for day of week $($resourceTzCurrentTime.DayOfWeek.value__)"
						}
					}
					else
					{
						throw "Schedule day of week $($resourceTzCurrentTime.DayOfWeek.value__) is missing Start Time (S) property."
					}
					
					if ($schedule.($resourceTzCurrentTime.DayOfWeek.value__).PSObject.Properties["E"] -ne $null)
					{
						try
						{
							$endTime = [int]::Parse($schedule.($resourceTzCurrentTime.DayOfWeek.value__).E)
						}
						catch
						{
							throw "Invalid End/Shutdown Time for day of week $($resourceTzCurrentTime.DayOfWeek.value__)"
						}
					}
					else
					{
						throw "Schedule day of week $($resourceTzCurrentTime.DayOfWeek.value__) is missing End/Shutdown Time (E) property."
					}

					Write-Output "Identified Start Time $startTime and End Time $endTime"

					#here we need to manage some special cases
					# StartTime -eq EndTime -> Skip
					# StartTime -eq 0 -> is 12AM
					# EndTime  -gt 23 -> don't turn it off

					if ($startTime -ne $endTime)
					{
						if ($startTime -lt $endTime)
						{
							Write-Output "     Checking if shutdown or startup should happen for vm $($vm.name)"
							Write-Output "     Start Time: $startTime"
							Write-Output "     End Time: $endTime"
							Write-Output "     Current Time: $($resourceTzCurrentTime.Hour)"
							
							# Performing some conversions in order to obtain the VM status
							$vmStatus = Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status

                            $vmStatusCode = $vmStatus.Statuses[1].Code
					
							Write-Output "     VM Status Code: $vmStatusCode"

							if (($resourceTzCurrentTime.Hour -ge $startTime) -and ($resourceTzCurrentTime.Hour -lt $endTime))
							{
								Write-Output "   Start - Comparing status code to check if it will be started or if it is already in this state."
								if ($vmStatusCode -eq "PowerState/deallocated" -or $vmStatusCode -eq "PowerState/stopped")
								{
									Write-Output "   VM $($vm.name) will be started."
									$vmsToStart += $vm
								}
							}
							elseif (($resourceTzCurrentTime.Hour -le $startTime) -or ($resourceTzCurrentTime.Hour -ge $endTime))
							{
								Write-Output "   Shutdown - Comparing status code to check if it will be shutdown or if it is already in this state."
								if ($vmStatusCode -eq "PowerState/running")
								{
									Write-Output "   VM $($vm.name) will be shutdown."
									$vmsToStop += $vm
								}
							}
						}
						else
						{
							Write-Output "VM $($vm.Name) contains a start time greater than shutdown time, evaluation will be skipped."
						}
					}
					else
					{
						Write-Output "VM $($vm.Name) contains schedule with equal start and end time, this prevents any action on this VM by the runbook."
					}
				}
				else
				{
					Write-Output "VM $($vm.Name) does not have definition for day of week $($resourceTzCurrentTime.DayOfWeek.value__) any evaluation will be skipped"
				}	  
			}
			else
			{
				Write-Output "VM $($vm.Name) does not have definition for time zone and any evaluation will be skipped"
			}
		}
		catch {
			Write-Error ('Issues processing VM {0} - {1} {2} - continuing with next VM' -f $vm.Name, $_.Exception, $error[0].ErrorDetails)
            $reportFailure=$true
		}
	}

$startVM={
    param($vmName, $resourceGroupName, $servicePrincipalConnection)
		Add-AzureRmAccount `
			-ServicePrincipal `
			-TenantId $servicePrincipalConnection.TenantId `
			-ApplicationId $servicePrincipalConnection.ApplicationId `
			-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    Start-AzureRMVM -Name $vmName -ResourceGroupName $resourceGroupName
}

$stopVM={
    param($vmName, $resourceGroupName, $servicePrincipalConnection)
		Add-AzureRmAccount `
			-ServicePrincipal `
			-TenantId $servicePrincipalConnection.TenantId `
			-ApplicationId $servicePrincipalConnection.ApplicationId `
			-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    Stop-AzureRMVM -Name $vmName -ResourceGroupName $resourceGroupName
}

$maxConcurrency=1
$jobTimeout=300
$jobs=@()

    foreach($vm in $vmsToStart) {
        write-output ('Starting {0}' -f $vm.Name)
        $jobs+=start-job -ScriptBlock $startVM -ArgumentList @($vm.Name, $vm.ResourceGroupName, $servicePrincipalConnection) -Name ('Start-{0}' -f $vm.Name)
        $timer=get-date
        do {
            $runningCount = (get-job -State Running).Count
            write-verbose ('Waiting for job to deque, current running count {0}' -f $runningCount)
            Start-Sleep -Seconds 30
            $timedout = ((get-date)-$timer).TotalSeconds -gt $jobTimeout
        } while ($runningCount -ge $maxConcurrency -and !$timedOut)
    }

    foreach($vm in $vmsToStop) {
        write-output ('Stopping {0}' -f $vm.Name)
        $jobs+=start-job -ScriptBlock $stopVM -ArgumentList @($vm.Name, $vm.ResourceGroupName, $servicePrincipalConnection) -Name ('Stop-{0}' -f $vm.Name)
        do {
            $runningCount = (get-job -State Running).Count
            write-verbose ('Waiting for job to deque, current running count {0}' -f $runningCount)
            Start-Sleep -Seconds 30
            $timedout = ((get-date)-$timer).TotalSeconds -gt $jobTimeout
        } while ($runningCount -ge $maxConcurrency -and !$timedOut)
    }

    wait-job -Job $jobs -Timeout $jobTimeout
    foreach($j in $jobs) {
        $job = get-job -job $j
        if ($job.State -ine 'Completed') {
            write-error ('Error in job {0}' -f $job.Name)
            $job
            $reportFailure=$true
        }
    }
<#
	# Starting VMs
	foreach -parallel -ThrottleLimit $vmsToStart.Count  ($vm in $vmsToStart)
	{
		Write-Output "Starting VM $($vm.name)"
		Start-AzureRmVM -Name $vm.name -ResourceGroupName $vm.ResourceGroupName 
	}

	# Stopping VMs
	foreach -parallel -ThrottleLimit $vmsToStop.Count  ($vm in $vmsToStop)
	{
		Write-Output "Stopping VM $($vm.name)"
		Stop-AzureRmVM -Name $vm.name -ResourceGroupName $vm.ResourceGroupName -Force
	}
#>
	Write-Output "End of runbook execution"
    if($reportFailure) {
        throw ('Generic non critical failure see error stream for details')
    }
#}
