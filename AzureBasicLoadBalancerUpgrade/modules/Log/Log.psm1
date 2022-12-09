function log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Position=0)]
        [Alias("level")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error','Verbose','Debug')]
        [string]$Severity = 'Information',

        [Parameter(Position=1)]
        [switch]
        $terminateOnError
    )

    Add-Content -Path ("Start-AzBasicLoadBalancerUpgrade.log") -Value ((Get-Date -Format 'yyyy-MM-dd hh:mm:ss.ffff') + " " + "[$Severity] - " + $Message) -Force
    $outputMessage = "[{0}]:{1}" -f $Severity,($Message -replace '\s\s+?','')
    If ($global:FollowLog) {
        switch ($severity) {
            "Error" {
                If ($terminateOnError.IsPresent) {
                    Write-Error $outputMessage -ErrorAction 'Stop'
                }
                Else {
                    Write-Error $outputMessage
                }
            }
            "Warning" {
                Write-Warning $outputMessage
            }
            "Information" {
                Write-Information $outputMessage -InformationAction Continue
            }
            "Verbose" {
                Write-Verbose $outputMessage
            }
            "Debug" {
                Write-Debug $outputMessage
            }
            default {
                Write-Information $outputMessage -InformationAction Continue
            }
        }
    }
    else {
        switch ($severity) {
            "Error" {
                If ($terminateOnError.IsPresent) {
                    Write-Error $outputMessage -ErrorAction 'Stop'
                }
                Else {
                    Write-Error $outputMessage
                }
            }
            "Warning" {
                Write-Warning $outputMessage
            }
        }
    }
}

Export-ModuleMember -Function log