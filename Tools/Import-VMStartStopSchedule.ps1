[CmdletBinding()]
param(
  [string] $webHook,
  [string] $csvFile,
  [String] $delimiter=';'
)

$schedules=import-csv -Path $csvFile -Delimiter $delimiter

foreach($schedule in $schedules) {
    
}


