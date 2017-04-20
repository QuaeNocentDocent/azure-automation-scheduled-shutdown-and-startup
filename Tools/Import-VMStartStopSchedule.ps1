[CmdletBinding()]
param(
  [string] $webHook,
  [string] $csvFile
)

$schedules=import-csv -Path $csvFile -Delimiter ','



