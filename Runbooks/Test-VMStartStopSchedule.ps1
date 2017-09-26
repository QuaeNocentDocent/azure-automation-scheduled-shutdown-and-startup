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
		$ScriptTagName='ScriptStartStopSchedule',		
		[Parameter(Mandatory=$false)]
		$ConnectionName='AzureRunAsConnection',
    [int] $maxConcurrency=50,
    [int] $jobTimeout=300,
    [string] $accountSubscriptionName='' #used in the special case where the automation account is not in the same sub of the VMs
		
	)
    
	function GetSchedule
	{
    [cmdletBinding()]
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
		$enabled=$tags[$EnableTagName]
    write-verbose ('Getting info for {0}. Value is: {1}' -f $EnableTagName, $tags[$EnableTagName])
		if ($enabled -eq 1) {return [string]$schedule}
		else {
			write-warning 'Schedule is disabled, skipping'
			return $null
		}
	}

  Function RunInHybrid
  {
    [cmdletBinding()]
      <# Standard Powershell JOb way. Alas it doesn't work cause the jobs don't get the certificate private key, this is really strange. I could have used a username/password pair, but it is not security wise, so decided to spawn automation jobs instead.
          Anyway let's keep the code in place, 'cause if it will ever work it is much lighter and faster #>
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
      ## MIssing shutdown script management  script=$vm.script.run
          Stop-AzureRMVM -Name $vmName -ResourceGroupName $resourceGroupName
      }

      write-warning 'Run On Hybrid not yet tested'

      $jobs=@()

          foreach($vm in $vmsToStart) {
              write-output ('Starting {0}' -f $vm.Name)
              $jobs+=start-job -ScriptBlock $startVM -ArgumentList @($vm.Name, $vm.ResourceGroupName, $servicePrincipalConnection) -Name ('Start-{0}' -f $vm.Name)              
          }

          foreach($vm in $vmsToStop) {
              write-output ('Stopping {0}' -f $vm.Name)
              $jobs+=start-job -ScriptBlock $stopVM -ArgumentList @($vm.Name, $vm.ResourceGroupName, $servicePrincipalConnection) -Name ('Stop-{0}' -f $vm.Name)
          }
    <#
              $timer=get-date
              do {
                  Start-Sleep -Seconds 30
                  $runningCount = (get-job -State Running).Count
                  $elapsed = ((get-date)-$timer).TotalSeconds
                  write-verbose ('Waiting for job to deque, current running count {0}, elapsed {1} secs' -f $runningCount, $elapsed)
                  $timedout = $elapsed -gt $jobTimeout
              } while ($runningCount -ge $maxConcurrency -and !$timedOut)
    #>              
      if($jobs.count -gt 0) {
          write-output 'Waiting for jobs completion'
          wait-job -Job $jobs -Timeout $jobTimeout
          $jobs | receive-job
          foreach($j in $jobs) {
              $job = get-job -id $j.id
              if ($job.State -ine 'Completed') {
                  write-error ('Error in job {0}' -f $job.Name)
                  $job
                  $global:reportFailure=$true
              }
          }
          $jobs | Remove-Job
      }
  }

  Function RunOnAzure
  {
    [cmdletBinding()]
    #Get current job Id

    $CurrentJobId= $PSPrivateMetadata.JobId.Guid
    if(! [String]::IsNullOrEmpty($accountSubscriptionName) -and (get-azurermcontext).Subscription.Name -ine $accountSubscriptionName) {
      $accountSub=Select-AzureRmSubscription -SubscriptionName $accountSubscriptionName -TenantId $servicePrincipalConnection.TenantId
      if (! $accountSub) {
          throw ('Invalid Automation Account Sub Specified {0}' -f $accountSubscriptionName)
      }
    }    
    write-verbose 'Detecting Automation Account Identity'
    $AutomationAccounts = Find-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts
    $AutomationAccountName=$null
    $AutomationAccountResourceGroupName=$null
    foreach ($item in $AutomationAccounts) 
    {
      # Loop through each Automation account to find this job
      $Job = Get-AzureRmAutomationJob -ResourceGroupName $item.ResourceGroupName -AutomationAccountName $item.Name -Id $CurrentJobId -ErrorAction SilentlyContinue
      if ($Job) 
      {
        $AutomationAccountName = $item.Name
        $AutomationAccountResourceGroupName = $item.ResourceGroupName
        $RunbookName = $Job.RunbookName #not used
        break
      }
    }
    #frist of all some checks
    #it happened that write-verbose statements are not executed after the Get-AzureRmAutomationJob statement
    if([String]::IsNullOrEmpty($AutomationAccountName) -or [String]::IsNullOrEmpty($AutomationAccountResourceGroupName)) {
        throw 'Missing accountNamer and ResourceGroupName needed to run on azure'
    }
    else {
      write-verbose ('Identified Automation Acoount {1} in resource group {0}' -f $AutomationAccountResourceGroupName, $AutomationAccountName)
    }
    $jobs=@()
    $expectedJobs=$vmsToStart.Count+$vmsToStop.Count

    foreach($vm in $vmsToStart) {
      try {
        write-output ('Starting {0}' -f $vm.Name)
        $jobs += Start-AzureRMAutomationRunbook -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'StartAzureVM' `
            -Parameters @{vmName=$vm.Name; resourceGroupName=$vm.ResourceGroupName; connectionName=$ConnectionName; subscriptionName=$SubscriptionName}
        $timer=get-date
      }
      catch {
        write-error ('Error starting {0}. Continuing' -f $vm.Name)
        $global:reportFailure=$true
      }
    }

    foreach($vm in $vmsToStop) {
      try {
        write-output ('Stopping {0}' -f $vm.Name)
        $params=@{
          vmName=$vm.Name
          resourceGroupName=$vm.ResourceGroupName
          connectionName=$ConnectionName
          subscriptionName=$SubscriptionName
          shutdownScript=$vm.script
        }
        write-verbose 'Dumping parameters'
        write-verbose $params.keys
        write-verbose $params.Values        
        $jobs += Start-AzureRMAutomationRunbook -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'StopAzureVM' `
            -Parameters $params
      }
      catch {
        write-error ('Error stopping {0}. Continuing' -f $vm.Name)
        $global:reportFailure=$true
      }
    }

    if($jobs.count -gt 0) {
      write-output 'Waiting for jobs completion'
      $timer=Get-Date
      do {
        Start-Sleep -Seconds 30
        $elapsed = ((get-date)-$timer).TotalSeconds
        $runningCount = (($jobs | get-azurermautomationjob) | where {$_.Status -notin @('Completed','Failed','Suspended')}).Count
        write-verbose ('Waiting for job to deque, current running count {0}, elapsed {1} secs' -f $runningCount, $elapsed)
        $timedOut = $elapsed -gt $jobTimeout        
      } while ($runningCount -gt 0 -and !$timedOut)

        #check if any failed
      $failedCount = (($jobs | get-azurermautomationjob) | where {$_.Status -in @('Failed','Suspended')}).Count
      if($failedCount -gt 0) {
        write-error ('Some actions have failed, see jobs log on azure automation. Failed Actions:{0}' -f $failedCount)
        $global:reportFailure=$true
      }
    }
    if($jobs.count -ne $expectedJobs) {
      write-error ('Some start/stop actions have failed. Expected jobs {0} actual jobs {1}' -f $expectedJobs, $jobs.Count)
      $global:reportFailure=$true
    }
  }

	# Getting Azure PS Version
	$azPsVer = (Get-Module -ListAvailable -Name Azure)[0]
	Write-Verbose "Azure PS Version $($azPsVer.Version.ToString())"

	$azRmPsVer = (Get-Module -ListAvailable -Name AzureRm.Compute)[0]
    
	Write-Verbose "Azure RM PS Version AzureRm.Compute $($azRmPsVer.Version.ToString())"

	# Authenticating and setting up current subscription
	Write-Output "Authenticating"
  $global:reportFailure=$false  #global to return a generic failure, set if any step fails even if the processing cvan continue. i.e. I cannot start a single VM, but the others are fine.
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
    if($azRmPsVer.Version.Major -eq 1) {
        #in this version we get an array of hashtables with keys name / value
        #let's transform it in a proper hashtable
        $rgTags=@{}
        foreach($t in $rg.tags) {
            $rgTags.Add($t.Name, $t.Value)
        }
    }
    else {
        $rgTags =$rg.Tags
    }		
		foreach ($vm in $vms)
		{
			Write-Output "VM to be evaluated: $($vm.name)"
      #now Azure Automation is a little messy with modules if you add the mess the Azure PS team introduced you know we're in trouble
      if($azRmPsVer.Version.Major -eq 1) {
          #in this version we get an array of hashtables with keys name / value
          #let's transform it in a proper hashtable
          $vmTags=@{}
          foreach($t in $vm.tags) {
              $vmTags.Add($t.Name, $t.Value)
          }
      }
      else {
          $vmTags =$vm.Tags       
      } 

			if ($vmTags.Keys -icontains $TagName)
			{
				write-verbose 'Schedule present on VM'
				$scheduleInfo = GetSchedule -tags $vmTags -TagName $tagName -EnableTagName $EnableTagName
				if ($scheduleInfo) {
					Write-verbose "   Resource Schedule for vm $($vm.name) is $scheduleInfo"
					#check if we have a script

					if($vmTags[$ScriptTagName]) {$scriptInfo=$vmTags[$ScriptTagName]} else {$scriptInfo=''}

					$vmObj = New-Object -TypeName PSObject -Property @{"Name"=$vm.Name;"ResourceGroupName"=$vm.ResourceGroupName;"Schedule"=$scheduleInfo;"Script"=$scriptInfo}
					$vmList += $vmObj
				}
			}
			else
			{
				if ($rgTags.Keys -icontains $TagName)
				{
					write-verbose 'Schedule present on RG'
					$scheduleInfo = GetSchedule -tags $rgTags -TagName $tagName -EnableTagName $EnableTagName
					if($scheduleInfo) {
						Write-verbose ('   Resource Group Schedule for vm {0} is {1}' -f $vm.name, ($scheduleInfo))
						if($rgTags[$ScriptTagName]) {$scriptInfo=$rgTags[$ScriptTagName]} else {$scriptInfo=''}						
						$vmObj = New-Object -TypeName PSObject -Property @{"Name"=$vm.Name;"ResourceGroupName"=$vm.ResourceGroupName;"Schedule"=$scheduleInfo;"Script"=$scriptInfo}
						$vmList += $vmObj
					}
				}
			}
		}
	}

	write-Output "VM tagged for start and stop => $($vmList.Count)"

	$vmsToStop = @()
	$vmsToStart = @()

	# Evaluating which VM will start and which will shutdown
	Write-Output "Evaluating which VM will start and which will shutdown"
	foreach ($vm in $vmList)
	{
		#I don't wnat to abort the entire process is a single VM has an invalid schedule
		try {
			Write-Output "   Evaluating vm $($vm.name)"
			Write-Verbose "   Getting Schedule"

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

					Write-Verbose "Identified Start Time $startTime and End Time $endTime"

					#here we need to manage some special cases
					# StartTime -eq EndTime -> Skip
					# StartTime -eq 0 -> is 12AM
					# EndTime  -gt 23 -> don't turn it off

					if ($startTime -ne $endTime)
					{
						if ($startTime -lt $endTime)
						{
							Write-Verbose "     Checking if shutdown or startup should happen for vm $($vm.name)"
							Write-Verbose "     Start Time: $startTime"
							Write-Verbose "     End Time: $endTime"
							Write-Verbose "     Current Time: $($resourceTzCurrentTime.Hour)"
							
							# Performing some conversions in order to obtain the VM status
							$vmStatus = Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status

                            $vmStatusCode = $vmStatus.Statuses[1].Code
					
							Write-Verbose "     VM Status Code: $vmStatusCode"

							if (($resourceTzCurrentTime.Hour -ge $startTime) -and ($resourceTzCurrentTime.Hour -lt $endTime))
							{
								Write-Verbose "   Start - Comparing status code to check if it will be started or if it is already in this state."
								if ($vmStatusCode -eq "PowerState/deallocated" -or $vmStatusCode -eq "PowerState/stopped")
								{
									Write-Output "*** VM $($vm.name) will be started."
									$vmsToStart += $vm
								}
							}
							elseif (($resourceTzCurrentTime.Hour -le $startTime) -or ($resourceTzCurrentTime.Hour -ge $endTime))
							{
								Write-Verbose "   Shutdown - Comparing status code to check if it will be shutdown or if it is already in this state."
								if ($vmStatusCode -eq "PowerState/running")
								{
									Write-Output "*** VM $($vm.name) will be shutdown."
									$vmsToStop += $vm
								}
							}
						}
						else
						{
							Write-Warning "VM $($vm.Name) contains a start time greater than shutdown time, evaluation will be skipped."
						}
					}
					else
					{
						Write-Warning "VM $($vm.Name) contains schedule with equal start and end time, this prevents any action on this VM by the runbook."
					}
				}
				else
				{
					Write-Warning "VM $($vm.Name) does not have definition for day of week $($resourceTzCurrentTime.DayOfWeek.value__) any evaluation will be skipped"
				}	  
			}
			else
			{
				Write-Warning "VM $($vm.Name) does not have definition for time zone and any evaluation will be skipped"
			}
		}
		catch {
			Write-Error ('Issues processing VM {0} - {1} {2} - continuing with next VM' -f $vm.Name, $_.Exception, $error[0].ErrorDetails)
      $global:reportFailure=$true
		}
	}

  $HybridWorkerRegKeyValues = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker" -ErrorAction SilentlyContinue
  try{
      If ($HybridWorkerRegKeyValues) {
          write-output 'Running on Hybrid using jobs'
          RunInHybrid
      }
      else {
          write-output 'Running on Azure using runbooks'
          RunOnAzure
      }
  }
  catch {
    #generic exception catcher
    write-error ('Exception executing actions on VMs. {0}' -f $_)
    $global:reportFailure=$true
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
    if($global:reportFailure) {
        throw ('Generic non critical failure see error stream for details')
    }
#}
