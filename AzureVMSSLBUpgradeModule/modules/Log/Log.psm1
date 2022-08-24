function log {
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter()]
        [Alias("level")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error','Verbose','Debug')]
        [string]$Severity = 'Information'
    )

    #Add-Content -Path ("AzureVMSSLBUpgradeModule-"+(Get-Date -Format FileDateTime)+".log") -Value ((Get-Date -Format 'yyyy-MM-dd hh:mm:ss.ffff') + " " + "[$Severity] - " + $Message) -Force
    Add-Content -Path ("AzureVMSSLBUpgradeModule.log") -Value ((Get-Date -Format 'yyyy-MM-dd hh:mm:ss.ffff') + " " + "[$Severity] - " + $Message) -Force
}

Export-ModuleMember -Function log