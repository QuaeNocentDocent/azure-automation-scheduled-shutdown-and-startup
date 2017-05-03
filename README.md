# azure-automation-scheduled-shutdown-and-startup
Repository for Azure Automation for Scheduled Startup and Shutdown of ARM Virtual Machines

Please refer to the following articles:

[Azure Automation – Using JSON formatted tags to create a week schedule for virtual machine startup and shutdown with Azure Automation Runbooks](https://blogs.technet.microsoft.com/paulomarques/2016/06/20/azure-automation-using-json-formatted-tags-to-create-a-week-schedule-for-virtual-machine-startup-and-shutdown-with-azure-automation-runbooks/)

[Azure Automation scenario: Using JSON-formatted tags to create a schedule for Azure VM startup and shutdown](https://azure.microsoft.com/en-us/documentation/articles/automation-scenario-start-stop-vm-wjson-tags/)

https://docs.microsoft.com/en-us/azure/automation/automation-sec-configure-azure-runas-account

Deployment steps:

- create an Automation Account and let it create a runas account for your Azure subscription or create your own runas account
- run Update Azure Modules, from Assets module
- deploy the solution New-AzureRmResourceGroupDeployment -ResourceGroupName management-weu -TemplateParameterFile .\azuredeploy.parameters.json -TemplateFile .\azuredeploy.json
- Check the hourly schedule created for you, the adice is to set the run time at 05 minutes in the hour
- if you want to use the helper script to set the schedules, create a webhook for the runbook wh-StartStopSchedule
- link the Test-VMStartStopSchedule to the Hourly schedule, since the runbook is potentially multi-subscription you must set the subscriptionName parameters and if you plan to run it on Azure the AccountName, AccountResourceGroupName, AccountSubscriptionName parameters with the identification of the automation account you're using. The latter are used to run the operations in parallel without the need to use powershell workflow.