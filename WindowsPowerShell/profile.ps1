<#
        .SYNOPSIS
        Common profile code for any host (ISE, VSCode, etc)

        .DESCRIPTION
        Undoes Write-Warning and Write-Host suppression, sets the prompt, then
        sideload or imports .\Modules\profile PSModule
#>

[CmdletBinding()]param()

#region pshtk replicated code : all.ps1 and .psm1: support sideloading

[string]$message = "Determining `$script:_psCommandPath"
Write-Verbose -Message $message

[bool]$local:isSideLoaded= $false

[string]$script:_psCommandPath = $null
[string]$script:_psScriptRoot  = $null
[string]$script:_baseName      = $null

if ( $PSCommandPath )
{
    $script:_psCommandPath = $PSCommandPath
}
elseif (
    ( 
        $local:variable = Get-Variable -Scope Global -Name __PSCommandPath* |
        Where-Object -Property Name -EQ -Value __PSCommandPath
    ) -and 
    (
        $local:path = $local:variable |
        Select-Object -ExpandProperty Value
    ) -and
    ( Test-Path -Path $local:path )
)
{
    $script:_psCommandPath = $local:path
    $local:isSideLoaded= $true
}
elseif (
    ( 'Windows PowerShell ISE Host' -eq $Host.Name ) -and
    ( Test-Path -Path $psISE.CurrentFile.FullPath )
)
{
    $script:_psCommandPath = $psISE.CurrentFile.FullPath
    $local:isSideLoaded= $true
}
else
{
    $message = "Unable to determine `$script:_psCommandPath and `$script:_psCommandPath"
    Write-Warning -Message $message
    Write-Error -Message $message -ErrorAction SilentlyContinue
}

if ( $script:_psCommandPath )
{
    $script:_psScriptRoot = Split-Path -Path $script:_psCommandPath -Parent
    $script:_scriptName   = Split-Path -Path $script:_psCommandPath -Leaf
    $script:_baseName     = ( Get-Item -Path $script:_psCommandPath ).BaseName

    "$script:_scriptName found`n`t" +
    "$script:_psCommandPath = '$script:_psCommandPath'`n`t" +
    "$script:_psScriptRoot  = '$script:_psScriptRoot'" |
    Write-Verbose
}

# so my linter stops complaining
if ( $script:_psScriptRoot -and $local:isSideLoaded -and $script:_baseName ) { $null }

#<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
#endregion pshtk replicated code : all.ps1 and .psm1: support sideloading
#region pshtk replicated code : all.ps1 : standard script header

$message = "$script:_scriptName started."

if ( 'ErrorAction' -notin $PSBoundParameters.Keys )
{
    $ErrorActionPreference = 'Stop'
}

if ( 'WarningAction' -notin $PSBoundParameters.Keys )
{
    $WarningPreference = 'Continue'
}

#<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
#endregion pshtk replicated code : all.ps1 : standard script header
#region profile.ps1 specific code

Set-Variable -Scope Global -Option ReadOnly -Name profileRoot -Value $script:_psScriptRoot
Set-Variable -Scope Global -Option ReadOnly -Name profileHome -Value $script:_psScriptRoot

# undo Write-Warning suppression
Set-Variable -Scope Global -Force -Name WarningAction -Value 'Continue'

# undo Write-Host suppression
Get-Item -Path Alias:Write-Host* |
Where-Object -Property Name -EQ -Value Write-Host |
Remove-Item -Force -ErrorAction SilentlyContinue

function prompt
{
    <#
            .SYNOPSIS
            Shell prompt.
    #>

    [CmdletBinding()]param()

    [Microsoft.PowerShell.Commands.HistoryInfo]$lastCommand = Get-History -Count 1

    if ( $lastCommand )
    {
        [int]$commandId = $lastCommand.Id + 1
        [TimeSpan]$commandTimeSpan = $lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime
    }
    else
    {
        [int]$commandId = 1
        [TimeSpan]$commandTimeSpan = [TimeSpan]::Zero
    }

    [string]$commandIdString = '{0:0000}' -f $commandId

    if ( !( Test-Path -Path 'Variable:Global: DNSHostName' ) )
    {
        [wmi]$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        [string]${global: DNSHostName} = $computerSystem.DNSHostName
    }

    Write-Host -NoNewline -ForegroundColor Cyan (
        "# ($( $commandTimeSpan.ToString( 'hh\:mm\:ss' ) )) $env:USERNAME@${Global: DNSHostName} " +
        "[$( [DateTime]::Now.ToString( 'yyyy\-MM\-dd' ) )]`n" +
        "# ($( [DateTime]::Now.ToString( 'HH\:mm\:ss' ) )) $PWD [$commandIdString] >$( '>' * $NestedPromptLevel )"
    )
    "`n"
}

#<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
#endregion profile.ps1 specific code
#region pshtk replicated code : all profile files : import $profile-specific PSModule

[string]$local:modulesRoot = Join-Path -Path $script:_psScriptRoot -ChildPath Modules

if ( $local:isSideLoaded )
{
    [string[]]$local:modulesPaths = 
    @( 
        ( Join-Path -Path $local:modulesRoot -ChildPath ( 
                Join-Path -Path $script:_baseName -ChildPath "$script:_baseName.psm1" 
        ) )
        ( Join-Path -Path $local:modulesRoot -ChildPath "$script:_baseName.psm1" )
    ) 
}
else
{
    [string[]]$local:modulesPaths = 
    @( 
        ( Join-Path -Path $local:modulesRoot -ChildPath $script:_baseName )
        ( Join-Path -Path $local:modulesRoot -ChildPath "$script:_baseName.psm1" )
    ) 
}

foreach ( $local:path in $local:modulesPaths )
{
    if ( !( Test-Path -Path $local:path ) )
    {
        continue
    }

    [bool]$local:success = $false

    [Management.Automation.ActionPreference]$local:oldWarningPreference = $global:WarningPreference

    try
    {
        [hashtable]$local:params =
        @{
            Scope              = 'Global'
            DisableNameChecking = $true
            Force               = $true
            ErrorAction         = 'Stop'
        }

        if ( $local:isSideLoaded )
        {
            $message = "$script:_scriptName sideloading '$path'"
            Write-Verbose -Message $message

            [string]$local:functionPath = "Function:$( Split-Path -Path $local:path -Leaf )"
            Get-Content -Raw -Path $local:path |
            Set-Content -Path $local:functionPath
            [ScriptBlock]$local:scriptBlock = Get-Content -Path $local:functionPath

            $message = "$script:_scriptName invoking New-Module ( Get-Content $local:functionPath )"
            Write-Verbose -Message $message
                
            [PSModuleInfo]$local:moduleInfo =
            New-Module -Name $local:functionPath -ScriptBlock $local:scriptBlock -ErrorAction Stop

            [string]$local:functionName = $local:moduleInfo.ExportedFunctions.Keys |
            Select-Object -First 1
                
            $message = "$script:_scriptName invoking Get-Command $local:functionName...| Remove-Module"
            Write-Verbose -Message $message
                
            Get-Command -Name $local:functionName* -All -CommandType Function |
            Where-Object -Property Name -EQ -Value $local:functionName |
            Where-Object -Property Module |
            Select-Object -ExpandProperty Module |
            Remove-Module -Force -ErrorAction SilentlyContinue
                
            $message = "$script:_scriptName invoking Import-Module -ModuleInfo `$local:moduleInfo"
            Write-Verbose -Message $message
                
            try
            {
                Set-Variable -Scope Global -Name __PSCommandPath -Value $local:path
                Import-Module -ModuleInfo $local:moduleInfo @local:params
            }
            catch
            {
                throw
            }
            finally
            {
                Remove-Variable -Scope Global -Name __PSCommandPath -Force -ErrorAction SilentlyContinue
            }

        } # if ( $isSideloaded )
        else
        {
            $message = "$script:_scriptName importing '$path'"
            Write-Verbose -Message $message

            Import-Module -Name $path @local:params
        }
        $success = $true
    }
    catch
    {
        Write-Warning -Message "$message threw exception:"
        $_ |
        Write-Warning
    }
    finally
    {
        $global:WarningPreference = $local:oldWarningPreference
    }
        
    # if it worked, stop looking
    if ( $success ) { break }

} # foreach ( $local:path in ...

#<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
#endregion pshtk replicated code : all profile files : import $profile-specific PSModule
#region pshtk replicated code : all.ps1 : standard script footer

foreach ( $i in 0 .. 9 ) { Write-Progress -Id ( $PID + $i ) -Completed -Activity ' ' -Status ' ' }
Write-Verbose -Message "$script:_scriptName finished."

#endregion pshtk replicated code : all.ps1 : standard script footer
# SIG # Begin signature block
# MIINFAYJKoZIhvcNAQcCoIINBTCCDQECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUmeZCbip8VfSv7DzioUdTtmi0
# uR+gggpWMIIFHjCCBAagAwIBAgIQCwaxDw7+GmN5XHzoDmBd4TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTIwMDgyODAwMDAwMFoXDTIzMDkw
# NjEyMDAwMFowWzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xETAP
# BgNVBAcTCEJlbGxldnVlMREwDwYDVQQKEwhUaW0gRHVubjERMA8GA1UEAxMIVGlt
# IER1bm4wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7GS2mf45t3zPT
# 1DaiNC8ERZsU0ERkZZIJlK5ZTDXLnVq3QrYunz1t/rhTqscnKM+dNTULa6KecjXF
# vzTwwKUEMht8G8SvxUknqK+45liTwKrsFNl7Ann4pmrVHIODSv7JhaOo18f7PbN5
# IlT8BnhBqnFRccYFqNnyQZOp4Wt3LOkYFHuVWhcvgjk0l2RUR5opvD99ZS1gHb8c
# tm32FTKtW2dtk5CPF1deGj0Sd5WaK52fuh/3JpdPsyASwIz5F7aXFzSsIxycbKYt
# 3CUvqgmg5lGexGgVzJMpvI43ubfpkDUm5qTRc04agqmKY8ow0hpubmr/gi/RAs++
# Ns8CsaaVAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32
# ZXUOWDAdBgNVHQ4EFgQUhPVq8ZwarLF8mAOgQM41XlgQxawwDgYDVR0PAQH/BAQD
# AgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Ax
# hi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNy
# bDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczov
# L3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUH
# MAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1
# cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEB
# CwUAA4IBAQCSxsD6k88y97TD+lDC3dDfloedxwkZiErinHD4z+y5nJV+8VBguKZ4
# 7p1LOXCy9Z60PGL0ZVjhZslpUFuG/XoYS4s6syknlkkiL+Ia00DOVeYon7s/4iep
# bzyv2erX+VFNTGWhK+GoXxr1dE+xTMJYkCXIIBoMFGnR9M0ybh+dGUuctcEQYido
# 2Mue8nNTMbxC30O4x/ySJBUvVSTrctt4E3tJ0QrwPBB7drglA5mZUNyZbuobEImk
# RdZSwOSXJ6oXvoaANRepqkoubi/CEPcxyYcy9VXK2TctHqsIjRhA3K41pYPyO7SJ
# 8aWjRqZaGjXs7I3y4tQ/ROttDwSgy4fiMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1
# U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQD
# ExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcN
# MjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid
# 2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sj
# lOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjf
# DPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzL
# fnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR
# 93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckw
# EgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYI
# KwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgw
# OqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIE
# MCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYI
# YIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQY
# MBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1a
# JLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUP
# UbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1
# UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjF
# Emifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM
# 1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhs
# RDKyZqHnGKSaZFHvMYICKDCCAiQCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8G
# A1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQ
# CwaxDw7+GmN5XHzoDmBd4TAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUkponVaDS0QeUFlS1dOfG
# PkOqtF4wDQYJKoZIhvcNAQEBBQAEggEAU1oKEWWjLGYVpY2toqmEb3wYw+E5kjI6
# o0K8Cjgs3qIOi5MUzMJipUqoPwni7oPKWSLWmdn0jOzeKYd22y4nGAsbpHTFQdJw
# QscNXalj35nmh6gnnOLIIGD8+GyyGKVitAz1G5kKP8H6VrDb2kkQk9KYV5OR9VlQ
# 8HVpYXnYB0X8FgimFe4qAnrBbM5PUmlelBXh/EX/O+QEJ8YcIUef8NPDsPiE7W8l
# rXoNWxy2KB8sRgul8IkNvjIJe++W+fexghlj0u/coWVk/8Kwidn1XdF+A+lJL8WH
# kKWklFq19iKebQm38s3aHVt3HClBe2poARBUBknaP22rgY3OToqbXA==
# SIG # End signature block
