function log {
    param(
        [Parameter(Mandatory = $True, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Position=0)]
        [Alias("level")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error','Verbose','Debug')]
        [string]$Severity = 'Information'
    )

    #Add-Content -Path ("AzureVMSSLBUpgradeModule-"+(Get-Date -Format FileDateTime)+".log") -Value ((Get-Date -Format 'yyyy-MM-dd hh:mm:ss.ffff') + " " + "[$Severity] - " + $Message) -Force
    Add-Content -Path ("AzureVMSSLBUpgradeModule.log") -Value ((Get-Date -Format 'yyyy-MM-dd hh:mm:ss.ffff') + " " + "[$Severity] - " + $Message) -Force

    If ([global]$FollowLog) {
        $outputMessage = "[{0}]:{1}" -f $Severity,$Message
    }

    Write-Output $outputMessage 
    switch ($severity) {
        "Error" {
            Write-Error $outputMessage
        }
        "Warning" {
            Write-Warning $outputMessage
        }
        "Information" {
            Write-Information $outputMessage -InformationAction SilentlyContinue
        }
        "Verbose" {
            Write-Verbose $outputMessage
        }
        "Debug" {
            Write-Debug $outputMessage
        }
    }

}

Export-ModuleMember -Function log