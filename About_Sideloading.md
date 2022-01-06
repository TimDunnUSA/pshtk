# About_Sideloading

## Overview

_Sideloading_ is the technique of creating `[ScriptBlock]` PSH objects, then dot-sourcing, invoking, or converting them to `[PSModuleInfo]` PSH objects to pass to `Import-Module`, thus bypassing restrictive `Set-ExecutionPolicy` settings or other means by which unsigned PowerShell scripts and PSModules cannot be used.

### Sideloading and Security

Sideloading is an intentional and deliberate effort to bypass security driven by a practical need: to develop Pester tests side-by-side with new code. A previous work environment disabled running unsigned scripts, importing unsigned PSModules, and updating the shell's format table data with `.ps1xml`. This led to multiple bad check-ins. The release cycle was measured in weeks, so each bad check-in resulted in two weeks negative impact.

Functionally, sideloading is an improvement over `[ScriptBlock]::Create()` because that oft-abused method is used to generate `[ScriptBlock]` PSH objects on-the-fly, whereas sideloading as implemented here works with files. This lends the following advantages:

- ISE IntelliSense can parse and highlight errors.

- Sideloaded Pester tests can test and detect errors.

- Sideloaded code, being only generated from files, provides an audit trail of just exactly what was invoked. Compare this to `& ( [ScriptBlock]::Create( $someStringGeneratedOnTheFly) )`.

- Sideloaded code changes are easily viewed in source control. Compare this to logically re-assembling the `$someStringGeneratedOnTheFly` from version to version.

## Sideloading How-To

### In the Beginning, There was the `[ScriptBlock]`

There are multiple ways to create `[ScriptBlock]` PSH objects. The previous work environment's source control back-end forbade `[ScriptBlock]::Create()`, so this project uses the `Function:` PSDrive.

**Example:**

```PowerShell
Get-Content -Raw -Path $profile |
Set-Content -Path Function:profile.ps1
[ScriptBlock]$scriptBlock = Get-Content -Path Function:profile.ps1
```

### Executing a Script

One common use case is to execute a given `.ps1` PSH script file. `[ScriptBlock] PSH objects lend themselves directly to this scenario from the prior example.

**Example:**

```PowerShel
C:\ PS> profile.ps1
```

Note the absence of any path specifier, relative or otherwise. PSH does _not_ include `$PWD` in the `$ENV:PATH`, so invoking `profile.ps1` will **not** cause PSH to search for any file by that name. Instead, [PSH Command Precedence](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence?view=powershell-5.1) takes over:

1. PSH aliases

1. PSH functions

1. PSH cmdlets

1. Non-PSH executables.

While `$PROFILE` does not take any parameters, sideloading via the `Function:` PSDrive creates a fully-fledged function that takes the same parameters as their `.ps1` PSH script file.

**Example:**

```PowerShell
C:\ PS> GenerateWeeklyReport.ps1 -Path 2022-01-05.csv -Destination $home\Reports\FY22Q3W1-sales.txt -Type Sales, Preorders
```

### Dot-Sourcing `$PROFILE`

`$PROFILE` code must be dot-sourced to modify the current shell. Invoking `profile.ps1` will create a new PSH subshell, execute the `profile.ps1` function, then close out the PSH subshell leaving the calling shell unchanged (unless the `profile.ps1` function makes globally-scoped changes such as `$global:variables` or calling `Set-Alias -Scope Global`)

This project sideloads profile files via:

**Example:**

```PowerShell
. ( Get-Content -Path Function:profile.ps1)
```

### Importing a PSModule

Sideloading a `.psm1` PSModule script file is a two step process: create the `[PSModuleInfo]` PSH object, then call `Import-Module -ModuleInfo` on that object.

**Example:**

```PowerShell
[Management.Automation.PSModuleInfo]$moduleInfo = New-ModuleInfo -Name $moduleName -ScriptBlock $scriptBlock
Import-Module -Scope Global -ModuleInfo $moduleInfo
```

**IMPORTANT:** Sideloading _only_ works on `.psm1` PSModule script files. It _cannot_ import a `.psd1` PSModule manifest file.

This can be inlined as `New-Module | Import-Module`, but the `[PSModuleInfo]` PSH object is necessary for another necessary step.

### Removing a Sideloaded PSModule

`New-Module` generates a unique pseudo-path each time it is called. Each `[PSModuleInfo]` PSH object refers to a _unique_ PSModule, so multiple PSModules with the same name and functions can be present in the shell simultaneously.

`Remove-Module` functions like `Get-Module` in that it may return a _subset_ of the PSModules present. However, `Remove-Module` does not expose the `-ListAvailable` nor the `-All` parameters available with `Get-Module`.

However, an intermittent `Remove-Module` bug removes only the `[PSModuleInfo]` _listing_ from the PSModule table (`$host.Runspace.InitialSessionState.Modules`), but leaves the _functions_ in the shell. Worse, they sometimes exist in the tab-completion list, but are _not_ found in the `Function:` PSDrive.

**Mitigation:**

```PowerShell
[string]$leftoverFunction = ( $moduleInfo ).ExportedFunctions.Keys |
Select-Object -First 1

Get-Command -All -Name $leftoverFunction* -CommandType Function |
Where-Object -Property Name
Select-Object -ExpandProperty Module | Remove-Module
```
