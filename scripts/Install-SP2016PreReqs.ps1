try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Install-SP2016PreReqs.ps1.txt -Append

    Start-Process D:\prerequisiteinstaller.exe -ArgumentList '/unattended' -Wait

    Restart-Computer
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}