Configuration SharePointServer {

    $password = ConvertTo-SecureString 'ThisWillLoadAtRunTime' -AsPlainText -Force
    $domainAdminCred = New-Object System.Management.Automation.PSCredential ('/aws-quickstart-sharepoint/domainAdmin', $password)

    Import-DscResource -ModuleName ComputerManagementDsc

    node localhost {

        Computer DomainJoin {
            Name = "{tag:Name}"
            DomainName = "{tag:QS-DomainName}"
            Credential = $domainAdminCred
        }

        Script SignalCFN {
            DependsOn = @(
                "[Computer]DomainJoin"
            )
            GetScript = { return @{} }
            TestScript = {
                try {
                    if ((Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart).SignalUrl -eq "{tag:QS-SignalUrl}") {
                        return $true
                    }
                    return $false
                } catch {
                    return $false
                }
            }
            SetScript = {
                Start-Process -FilePath "cfn-signal.exe" -ArgumentList @() -PassThru -Wait
                New-Item -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                Set-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -Name SignalUrl -Value "{tag:QS-SignalUrl}"
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
