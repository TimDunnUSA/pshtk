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
#region profile.psm1 specific code
function Get-AbstractSyntaxTree
{
    <#
            .SYNOPSIS
            Get Abstract Syntax Tree for PowerShell files.

            .PARAMETER Path
            File to parse.

            .INPUTS
            [string[]]

            .OUTPUTS
            [PSCustomObject]

            AST         : [Management.Automation.Language.ScriptBlockAst]
            Tokens      : [Management.Automation.Language.Token[]]
            ParseErrors : [Management.Automation.Language.ParseError[]]
            Path        : [string]

            .LINKS
            https://adamtheautomator.com/powershell-ast/
    #>

    #[CmdletBinding()]

    param
    (
        [Parameter( ValueFromPipeline, ValueFromPipelineByPropertyName, ValueFromRemainingArguments, Position = 0 )]
        [string[]]$Path = @()
    )

    begin
    {
        [string]$local:functionName = $MyInvocation.MyCommand.Name
        [string]$message = "$local:functionName started."
        Write-Verbose -Message $message

        if ( 'ErrorAction' -notin $PSBoundParameters.Keys ) { $ErrorActionPreference = 'Stop' }
    }

    process
    {
        $Path |
        ForEach-Object -Process `
        {
            if ( Test-Path -Path $_ )
            {
                Get-ChildItem -Path $_ -File |
                Where-Object -Property Length |
                Where-Object -Property Extension -In -Value '.ps1', '.psm1' |
                ForEach-Object -Process `
                {
                    [IO.FileInfo]$fileInfo = $_

                    [Management.Automation.Language.Token[]]$tokens = @()
                    [Management.Automation.Language.ParseError[]]$parseErrors = @()

                    $message = "$local:functionName -Path $( $fileInfo.FullName )"
                    Write-Verbose -Message $message

                    try
                    {

                        [Management.Automation.Language.ScriptBlockAst]$ast =
                        [Management.Automation.Language.Parser]::ParseFile(
                            $fileInfo.FullName,
                            [ref]$tokens,
                            [ref]$parseErrors
                        )
                    }
                    catch
                    {
                        Write-Warning -Message "$message threw exception:"
                        $_ | Write-Warning
                    }
                    finally
                    {
                        [PSCustomObject]$outputObject = [PSCustomObject][ordered]`
                        @{
                            AST         = $ast
                            Tokens      = $tokens
                            ParseErrors = $parseErrors
                            FileInfo    = $fileInfo
                        }

                        $outputObject.PSObject.TypeNames.Add( 'PshTK.AST.Parsed' )
                        $outputObject

                    } # try {} catch{} finally{}

                } # Get-ChildItem ... | ForEach-Object

            } # if ( Test-Path -Path $_ )

        } # $Path | ForEach-Object

    } # process

    end
    {
        Write-Verbose -Message "$local:functionName finished."
    }

    #> # function Get-AbstractSyntaxTree
    #<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
}

function Set-Function
{
    <#
            .SYNOPSIS
            Turn a PowerShell script into a PowerShell function.

            .DESCRIPTION
            Create PowerShell function from existing file. This bypasses ExecutionPolicy restrictions.

            .PARAMETER Path
            Path to file or folder of files.

            .PARAMETER PassThru
            Output [FunctionInfo] outputs created.

            .INPUTS
            [IO.FileSystemInfo[]]

            .OUTPUTS
            [Management.Automation.FunctionInfo[]] if -PassThru specified, [void] otherwise.

            .EXAMPLE
            Set-Function -Path .\try-it.ps1 -PassThru

            CommandType     Name                                               Version    Source
            -----------     ----                                               -------    ------
            Function        try-it
    #>

    #[CmdletBinding()]

    param
    (
        [Parameter( ValueFromPipeline, ValueFromPipelineByPropertyName, ValueFromRemainingArguments, Position = 0 )]
        [string[]]$Path = @(),

        [switch]$PassThru,

        [switch]$Force
    )

    begin
    {
        [string]$local:functionName = $MyInvocation.MyCommand.Name
        [string]$message = "$local:functionName started."
        Write-Verbose -Message $message

        if ( 'ErrorAction' -notin $PSBoundParameters.Keys ) { $ErrorActionPreference = 'Stop' }
    }

    process
    {
        # queue up the output
        [Management.Automation.FunctionInfo[]]$functionInfo = $Path |
        Get-AbstractSyntaxTree |
        Where-Object -Property AST |
        ForEach-Object -Process `
        {
            [PSCustomObject]${pshTK.AST.Parsed} = $_
            [IO.FileInfo]$fileInfo = ${pshTK.AST.Parsed}.FileInfo
            [string]$fullName = $fileInfo.FullName

            $message = "$local:functionName -Path $fullName"
            Write-Verbose -Message $message

            try
            {
                if ( ${pshTK.AST.Parsed}.ParseErrors.Count )
                {
                    throw ( (, 'Parse errors:' ) + ${pshTK.AST.Parsed}.ParseErrors )
                }

                if (
                    !$Force -and
                    (
                        ${pshTK.AST.Parsed}.AST.FindAll(
                            { $args[0] -is [Management.Automation.Language.VariableExpressionAst] },
                            $false
                        ) |
                        Where-Object -Property VariablePath -In -Value PSScriptRoot, PSCommandPath
                    )
                )
                {
                    throw "Is not compatible with scripts that use `$PSScriptRoot or `$PSCommandPath."
                }

                [string]$destination = 'Function:' + $fileInfo.BaseName

                $message = "$local:functionName creating $destination"
                Write-Verbose -Message $message

                Get-Content -Raw -Path $fullName |
                Set-Content -Path $destination

                Get-Item -Path $destination
            }
            catch
            {
                Write-Warning -Message "$message threw exception:"
                $_ |
                Write-Warning
            }

        } # $Path | ForEach-Object

        $functionInfo |
        Out-TableString -Indentation 9 -Header "$local:functionName created" |
        Write-Verbose

        if ( $PassThru ) { $functionInfo }
    }

    end
    {
        Write-Verbose -Message "$local:functionName finished."
    }

    #> # function Set-Function
    #<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
}

# function New-ProxyFunction
# {
#     <#
#     #>
#     #> # function New-ProxyFunction
#     #<#' #><#" #><#) #><#] #><#} #># keep edits above this line from unfolding code below this line
# }

#endregion profile.psm1 specific code
# SIG # Begin signature block
# MIINFAYJKoZIhvcNAQcCoIINBTCCDQECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEouP5z6A2y0tCD82hWnx+a/I
# NfagggpWMIIFHjCCBAagAwIBAgIQCwaxDw7+GmN5XHzoDmBd4TANBgkqhkiG9w0B
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
# MQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUQYb3cV+/UgYGfK5hjnFn
# RR2sHxIwDQYJKoZIhvcNAQEBBQAEggEAHkqUN/JlRo4pEhrDOr/jWWYJkEkLCLh9
# CVl8WFATb9UvPdDPu+xgacHQG1rsB33+fx1QxZy7yy+nK5PzAs2w44gzYILcL6zQ
# /Pi0fYprPiQzMJv4pOOH83fy9+2wiMBbPrPDOHG3/LTWr8y32p62V+8FSc0MMniV
# QrrhUD0J4Tjmsk2gwOYiaKskL4FjNynVKH/nkveBJbAbex3oYNFBUqkJPHyqyEtj
# Y82sFcd74YNV4zvz8j/Cfp+nFb4zrY2CzwGGEW81ZvX0kKlWsh+zieN7VljELuMx
# nEGJcj4B198F87Ipi0W78URcL8FGavlNkEYkk3wSKVVoQQjHW/vKtw==
# SIG # End signature block
