try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Install-SP2016PreReqs.ps1.txt -Append

    $driveLetter = Get-Volume | ?{$_.DriveType -eq 'CD-ROM'} | select -ExpandProperty DriveLetter
    if ($driveLetter.Count -gt 1) {
        throw "More than 1 mounted ISO found"
    }

    Start-Process "$($driveLetter):\prerequisiteinstaller.exe" -ArgumentList '/unattended' -Wait

    Restart-Computer
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}