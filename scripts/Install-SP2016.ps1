[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SQLServer,

    [Parameter(Mandatory=$true)]
    [string]$SPFarmAccount,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [Parameter(Mandatory=$true)]
    [string]$Key,

    [Parameter(Mandatory=$true)]
    [ValidateSet("WebFrontEnd","Application","DistributedCache","Search","SingleServerFarm","Custom")]
    [string]$ServerRole,

    [Parameter(Mandatory=$false)]
    [switch]$CreateFarm
)

try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Install-SP2016.ps1.txt -Append

    if($Key -ne "NQGJR-63HC8-XCRQH-MYVCH-3J3QR"){
        $config = cat C:\cfn\scripts\config2016.xml
        $config = $config.replace("NQGJR-63HC8-XCRQH-MYVCH-3J3QR",$Key)
        Set-Content -Path C:\cfn\scripts\config2016.xml -Value $config
    }

    Start-Process D:\setup.exe -ArgumentList '/config c:\cfn\scripts\config2016.xml'

    #pause while installing...
    while(Get-Process setup -ErrorAction 0) {Start-Sleep -Seconds 30}

    New-Item HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\ -EA 0
    New-ItemProperty HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\ -Name SQL -Value "DBMSSOCN,$SQLServer"

    $pass = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $SPFarmAccount,$pass

    Add-PSSnapin *sharepoint*
    if($CreateFarm) {
        New-SPConfigurationDatabase -LocalServerRole $ServerRole -DatabaseServer SQL -DatabaseName SPConfigDB -AdministrationContentDatabaseName AdminDB -PassPhrase (ConvertTo-SecureString $Password -AsPlainText -Force) -FarmCredentials $cred
        New-SPCentralAdministration –Port 18473 –WindowsAuthProvider NTLM
    }
    else {
        Connect-SPConfigurationDatabase -LocalServerRole $ServerRole -DatabaseServer SQL -DatabaseName SPConfigDB -Passphrase (ConvertTo-SecureString $Password -AsPlainText -Force)
    }

    Install-SPHelpCollection -All
    Initialize-SPResourceSecurity
    Install-SPService
    Install-SPFeature -AllExistingFeatures –Force
    Install-SPApplicationContent

    $timerServiceName = "SPTimerV4"
    $timerService = Get-Service $timerServiceName
    if ($timerService.Status -ne "Running") {
        Start-Service $timerServiceName
    }
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}