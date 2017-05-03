[CmdletBinding()]
param(
    [Parameter (Mandatory=$true)]
    [string] $webHook,
    [Parameter (Mandatory=$true)]
    [string] $csvFile,
    [String] $delimiter=';',
    [Parameter(Mandatory=$true)]
    [string] $subscriptionName,
    [string] $tagName='StartStopSchedule',
    [string] $enableTagName='EnableStartStopSchedule',
    [string] $scriptTagName='ScriptStartStopSchedule',    
    [string] $connectionName
)

function parsetime
{
    param([int] $day, [object] $time)

 $interval=($time.($dayMap[$day])).Replace('|',';') -split ';'

    return @{
        'S'=$interval[0]
        'E'=$interval[1]
    }

}

$dayMap=@{
    0='Sun'
    1='Mon'
    2='Tue'
    3='Wed'
    4='Thu'
    5='Fri'
    6='Sat'
}


$schedules=import-csv -Path $csvFile -Delimiter $delimiter

#$headers = @{"Date"=(get-date).ToUniversaltime().GetDateTimeFormats('u')}

foreach($schedule in $schedules) {
    write-output ('Processing {0} in resource group {1}' -f $schedule.VM, $schedule.ResourceGroup)
    ##create a schedule
    if($schedule.enabled -eq 0) {$enabled=$false} else {$enabled=$true}

    $scheduleHash= @{
        "TzId"=$schedule.TimeZone
        "0"= ParseTime -Day 0 -Time $schedule
        "1"= ParseTime -Day 1 -Time $schedule
        "2"= ParseTime -Day 2 -Time $schedule
        "3"= ParseTime -Day 3 -Time $schedule
        "4"= ParseTime -Day 4 -Time $schedule
        "5"= ParseTime -Day 5 -Time $schedule
        "6"= ParseTime -Day 6 -Time $schedule

    }
    $scriptHash=@{
        "run"=$schedule.StopScript
    }
  $payload =@{
    'action'='set'
    'parameters'=@{
        "subscriptionName"=$subscriptionName
        "resourceGroupName"=$schedule.ResourceGroup
        "vmName"=$schedule.VM
        "schedule"=$scheduleHash
        "tagName"=$tagName
        "enableTagName"=$enableTagName
        "scriptTagName"=$scriptTagName
        "script"=$scriptHash
        "enabled"=$enabled
        "connectionName"=$connectionName
    }
  }

  $body = ConvertTo-Json -InputObject $payload -Depth 4 -Compress

  $response = Invoke-RestMethod -Method Post -Uri $webHook -Headers $headers -Body $body -UseBasicParsing
  #$jobid = ConvertFrom-Json $response
  write-output "AUtomation job submitted with id $($response.JobIds)"
}

