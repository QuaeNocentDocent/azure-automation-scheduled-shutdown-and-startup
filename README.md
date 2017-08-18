# azure-automation-scheduled-shutdown-and-startup
Repository for Azure Automation for Scheduled Startup and Shutdown of ARM Virtual Machines

Please refer to the following articles:

[Azure Automation – Using JSON formatted tags to create a week schedule for virtual machine startup and shutdown with Azure Automation Runbooks](https://blogs.technet.microsoft.com/paulomarques/2016/06/20/azure-automation-using-json-formatted-tags-to-create-a-week-schedule-for-virtual-machine-startup-and-shutdown-with-azure-automation-runbooks/)

In addition to the format specified in the article we have:

- a tag (defualts to ) to Enable (=1) or disable the schedule (=0) so it's easy to temporarily suspend the start/stop form a VM/RG from the portal
- a tag (dafults to ) to specify a shutdown script to be run before turning off the VM. The json payload is {"run":"command line", "timeout": 60}. Where the timeout is in seconds. In this version we support only shutdown script (not start up but they're an easy add) and scripts that are local to the VM. 
- for a given week day:
  - if StartTime -eq EndTime we do nothing (skip)
  - StartTime -eq 0 means 12AM
  - EndTime -gt 23 means don't turn it off

[Azure Automation scenario: Using JSON-formatted tags to create a schedule for Azure VM startup and shutdown](https://azure.microsoft.com/en-us/documentation/articles/automation-scenario-start-stop-vm-wjson-tags/)

https://docs.microsoft.com/en-us/azure/automation/automation-sec-configure-azure-runas-account

Deployment steps:

- create an Automation Account and let it create a runas account for your Azure subscription or create your own runas account
- run Update Azure Modules, from Assets module
- deploy the solution New-AzureRmResourceGroupDeployment -ResourceGroupName management-weu -TemplateParameterFile .\azuredeploy.parameters.json -TemplateFile .\azuredeploy.json
- Check the hourly schedule created for you, I advise to set the run time at 05 minutes in the hour
- if you want to use the helper script to set the schedules, create a webhook for the runbook wh-StartStopSchedule
- link the Test-VMStartStopSchedule to the Hourly schedule, since the runbook is potentially multi-subscription you must set the subscriptionName parameters and if you plan to run it on Azure and the Automation Account is in a different subscription from the managed VMs you must set the AccountSubscriptionName parameterg. The latter are used to run the operations in parallel without the need to use powershell workflow.

## Accelerator

Since manually editing the json tag is far from optimal from the Ibiza Portal a combination of an Excel Spreadsheet (saved in CSV format) and an Helper script (Import-VMStartStopSchedule.ps1) that invokes a web hook can be used to set the proper scheduling.
The CSV file must have the following format, all the columns after 'Sat' are ignored and can be used for documentation purposes.

| ResourceGroup | VM | Enabled | StopScript | ScriptTimeout | TimeZone | Sun | Mon | Tue | Wed | Thu | Fri | Sat | Description | Notes |
|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
|preAzureSdk1|preAzureSdk1|1|powershell.exe -ExecutionPolicy Unrestricted -file c:\\temp\\test.ps1|150|Central European Standard Time|0&#124;0|8&#124;20|8&#124;20|8&#124;20|8&#124;20|8&#124;20|0&#124;0|turned off 8:00 PM --> 8:00 AM (Alway Saturday and Sunday)|||	
|GollumOnDocker|GollumD|1|sh /tmp/test.sh|60|Central European Standard Time|0&#124;0|8&#124;20|8&#124;20|8&#124;20|8&#124;20|8&#124;20|0&#124;0|turned off 8:00 PM --> 8:00 AM (Alway Saturday and Sunday)|||

