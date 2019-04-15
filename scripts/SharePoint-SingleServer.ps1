Configuration SharePointServer {

    $password = ConvertTo-SecureString 'ThisWillLoadAtRunTime' -AsPlainText -Force
    $SPSetupAccount            = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSetupAccount}', $password)
    $FarmAccount               = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPFarmAccount}', $password)
    $Passphrase                = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPPassPhrase}', $password)
    $ServicePoolManagedAccount = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSvcAppAccount}', $password)
    $WebPoolManagedAccount     = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPWebAppAccount}', $password)
    $SuperUserAccount          = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSuperUserAccount}', $password)
    $SuperReaderAccount        = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPWebAppAccount}', $password)
    $UPSyncAccount             = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPReaderAccount}', $password)
    $CrawlAccount              = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPCrawlAccount}', $password)
    $domainAdminCredential     = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${ADAdminSecretArn}', $password)

    Import-DscResource -ModuleName xCredSSP              -ModuleVersion 1.0.1
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 6.2.0.0
    Import-DscResource -ModuleName StorageDsc            -ModuleVersion 4.6.0.0
    Import-DscResource -ModuleName xActiveDirectory      -ModuleVersion 2.25.0.0

    node localhost {

        Environment VersionStamp {
            Name = "QuickStartVersion"
            Value = "2.0.0"
        }

        # Putting this before the domain join means that the copy from S3 has time to succeed before the domain join reboot
        Script WaitForBinaries {
            GetScript = { return @{} }
            TestScript = {
                return (Get-Item C:\config\sources\installer.zip -ErrorAction SilentlyContinue).Length -ne 0
            }
            SetScript = {
                $count = 0
                while ((Get-Item C:\config\sources\installer.zip -ErrorAction SilentlyContinue).Length -eq 0 -and $count -lt 10) {
                    $count++
                    Start-Sleep -Seconds 30
                }
            }
        }

        Computer DomainJoin {
            Name = "{tag:Name}"
            DomainName = '${DomainDNSName}'
            Credential = $domainAdminCredential
            DependsOn = "[Script]WaitForBinaries"
        }

        Disk SecondaryDisk {
            DiskId = 1
            DriveLetter = 'D'
            PartitionStyle = 'MBR'
            FSFormat = 'NTFS'
        }

        Archive UnzipSpInstaller
        {
            Path        = "C:\config\sources\installer.zip"
            Destination = "D:\binaries"
            Ensure      = "Present"
            DependsOn   = "[Disk]SecondaryDisk"
        }

        xCredSSP CredSSPServer 
        { 
            Ensure = "Present" 
            Role = "Server" 
            DependsOn = "[Computer]DomainJoin"
        } 

        xCredSSP CredSSPClient 
        { 
            Ensure = "Present" 
            Role = "Client" 
            DelegateComputers = '*.${DomainDNSName}'
            DependsOn = "[Computer]DomainJoin"
        }

        @(
            "RSAT-ADDS", 
            "RSAT-AD-AdminCenter", 
            "RSAT-ADDS-Tools", 
            "RSAT-AD-PowerShell" 
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            { 
                Ensure = "Present" 
                Name = $_
            }
        }

        $userAccounts = @{
            "svcSPSetup" = $SPSetupAccount
            "svcSPFarm" = $FarmAccount
            "svcSPWebApp" = $WebPoolManagedAccount
            "svcSPSvcApp" = $ServicePoolManagedAccount
            "svcSPCrawl" = $CrawlAccount
            "svcSPUPSync" = $UPSyncAccount
            "svcSPSuperUser" = $SuperUserAccount
            "svcSPReader" = $SuperReaderAccount
        }

        $userAccounts.Keys | ForEach-Object -Process {
            xADUser "User-$_"
            { 
                DomainName = '${DomainDNSName}'
                DomainAdministratorCredential = $domainAdminCredential 
                UserName = $_ 
                Password = $userAccounts[$_]
                Ensure = "Present" 
                DependsOn = "[WindowsFeature]Feature-RSAT-AD-PowerShell" 
            }
        }

        Script SignalCFN {
            DependsOn = @(
                "[Computer]DomainJoin"
            )
            GetScript = { return @{} }
            TestScript = {
                $value = Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                if ($null -eq $value) { return $false }
                if ($value.SignalSent -eq $true) { return $true }
                return $false
            }
            SetScript = {
                Start-Process -FilePath "cfn-signal.exe" -ArgumentList @("-s", "true", (Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart).SignalUrl) -PassThru -Wait
                New-Item -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                Set-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -Name SignalSent -Value $true
            }
        }
    }
}

SharePointServer -OutputPath .\MOF -ConfigurationData @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
        }
    )
}
