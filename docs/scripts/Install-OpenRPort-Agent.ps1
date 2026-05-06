<#
        .SYNOPSIS
        Installs the rport clients and connects it to the server

        .DESCRIPTION
        This script will download the latest version of the rport client,
        create the configuration and connect to the server.
        You can change the configuration by editing C:\Program Files\rport\rport.conf
        Rport runs as a service with a local system account.

        .PARAMETER x
        Enable the execution of scripts via rport.

        .PARAMETER t
        Use the latest unstable development release. Dangerous!

        .PARAMETER i
        Install Tascoscript along with the RPort Client

        .PARAMETER r
        Enable file recption

        .PARAMETER g
        Add a custom tag

        .PARAMETER d
        Write the config and exit. Service will not be installed. Mainly for testing.

        .INPUTS
        None. You cannot pipe objects.

        .OUTPUTS
        System.String. Add-Extension returns success banner or a failure message.

        .EXAMPLE
        PS> powershell -ExecutionPolicy Bypass -File .\rport-installer.ps1 -x
        Install and connext with script execution enabled.

        .EXAMPLE
        PS> powershell -ExecutionPolicy Bypass -File .\rport-installer.ps1
        Install and connect with script execution disabled.

        .LINK
        Online help: https://kb.openrport.io/connecting-clients#advanced-pairing-options
#>
#Requires -RunAsAdministrator
# Definition of command line parameters
Param(
    [Alias("EnableCommands")][switch]$x = $True, # Enable remote commands yes/no
    [switch]$t, # Use unstable version yes/no
    [switch]$i = $True, # Install tacoscript
    [switch]$r = $True, # Enable file reception
    [string]$g, # Add a tag
    [switch]$d, # Exit after writing the config
    [string]$pkgUrl
)
if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64")
{
    Write-Output "Only 64bit Windows on x86_64 supported. Sorry."
    Exit 1
}

# BEGINNING of templates/header.txt ----------------------------------------------------------------------------------|

##
## This is the RPort client installer script.
## It helps you to quickly install the rport client on a variety of Linux distributions.
## The scripts creates a initial configuration and connects the client to your server.
##
## For any inquiries use our GitHub forum on
## https://github.com/openrport/rport-pairing/discussions/
##
## Copyright cloudradar GmbH, Potsdam Germany, 2022
## Maintainer openrport, Lille, France, 2023
## Released under the MIT open-source license.
## https://github.com/openrport/rport-pairing/blob/main/LICENSE
##
# END of templates/header.txt ----------------------------------------------------------------------------------------|

## BEGINNING of rendered template templates/windows/vars.ps1
#
# Dynamically inserted variables (placeholders — populated by the pairing service at request time)
#
$fingerprint = "REPLACE_WITH_SERVER_FINGERPRINT"
$connect_url = "REPLACE_WITH_CONNECT_URL"
$client_id   = "REPLACE_WITH_CLIENT_ID"
$password    = "REPLACE_WITH_PASSWORD"
## END of rendered template templates/windows/vars.ps1


# BEGINNING of templates/windows/functions.ps1 -----------------------------------------------------------------------|

$InformationPreference = "continue"
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues = @{ '*:Encoding' = 'utf8' }
trap
{
    "
#
# -------------!!   ERROR  !!-------------
#
# Installation or updare of rport finished with errors.
#

Error in line $( $_.InvocationInfo.ScriptLineNumber )
    $_

Try the following to investigate:
1) sc query rport

2) open C:\Program Files\rport\rport.log

3) READ THE DOCS on https://kb.openrport.io

4) Request support on https://github.com/openrport/rport-pairing/discussions/categories/help-needed
"
    Set-Location $myLocation
    exit 1
}

$InstallerLogFile = $false
if (-not(Get-Command Write-Information -erroraction silentlycontinue))
{
    $InstallerLogFile = (Get-Location).path + "\rport-installer.log"
    if (Test-Path $InstallerLogFile)
    {
        Remove-Item $InstallerLogFile
    }
    Write-Output "# Compatibility mode for PowerShell $( $PSVersionTable.PSVersion ) activated"
    Write-Output "# All information stream messages are redirected to $( $InstallerLogFile )"
    function Write-Information
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Applies only to old PS Versions')]
        Param(
            [parameter(Mandatory = $false)]
            [String] $MessageData = ""
        )
        Add-Content -Path $InstallerLogFile -Value $MessageData
    }
}

function Get-Log
{
    if (Test-Path $InstallerLogFile)
    {
        Write-Output ""
        Write-Output "= The following information has been logged:"
        Get-Content $InstallerLogFile
        Remove-Item $InstallerLogFile -Force
    }
}

# Extract a ZIP file
function Expand-Zip
{
    Param(
        [parameter(Mandatory = $true)]
        [String] $Path,
        [parameter(Mandatory = $true)]
        [String] $DestinationPath
    )
    if (Get-Command Expand-Archive -errorAction SilentlyContinue)
    {
        Expand-Archive -Path $Path -DestinationPath $DestinationPath -force
    }
    else
    {
        # Use a fallback for old powershells < 5
        Remove-Item (-join ($DestinationPath, "\*")) -force -Recurse
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $DestinationPath)
    }
}

function Add-ToConfig
{
    [OutputType([String])]
    Param(
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent,
        [parameter(Mandatory = $true)]
        [String] $Block,
        [parameter(Mandatory = $true)]
        [String] $Line
    )
    <#
    .SYNOPSIS
        Add a line to a block of a the rport toml configuration.
    #>
    if ($configContent -NotMatch "\[$block\]")
    {
        # Append the block if missing
        $configContent = "$configContent`n`n[$block]"
    }
    Write-Information "* Adding `"$Line`" to [$Block]"
    $configContent = $configContent -replace "\[$Block\]", "$&`n  $Line"
    $configContent
}

function Find-Interpreter
{
    <#
    .SYNOPSIS
        Find common script interpreters installed on the system
    #>
    $interpreters = @{
    }
    if (Test-Path -Path 'C:\Program Files\PowerShell\7\pwsh.exe')
    {
        $interpreters.add('powershell7', 'C:\Program Files\PowerShell\7\pwsh.exe')
    }
    if (Test-Path -Path 'C:\Program Files\Git\bin\bash.exe')
    {
        $interpreters.add('bash', 'C:\Program Files\Git\bin\bash.exe')
    }
    $interpreters
}

function Enable-FileReception
{
    [OutputType([String])]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent,
        [Parameter(Mandatory)]
        [Boolean]$Switch
    )

    if ($Switch)
    {
        try
        {
            $ConfigContent = Set-TomlVar -ConfigContent $ConfigContent "file-reception" -Key "enabled" -value "true"
            Write-Information "* File reception has been enabled."
        }
        catch
        {
            Write-Information ": Enabling file-reception failed."
            Write-Information ": Check the settings of [file-reception] manually and change to your needs."
        }

    }
    else
    {
        try
        {
            $ConfigContent = Set-TomlVar -ConfigContent $ConfigContent "file-reception" -Key "enabled" -value "false"
            Write-Information "* File reception has been disabled."
        }
        catch
        {
            Write-Information ": Disabling file-reception failed."
            Write-Information ": Check the settings of [file-reception] manually and change to your needs."
        }

    }


    $ConfigContent
    return
}

function Enable-InterpreterAlias
{
    <#
    .SYNOPSIS
        Push interpreters to the rport.conf
    #>
    [OutputType([Object[]])]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent
    )

    Write-Information "* Looking for script interpreters."
    $interpreters = Find-Interpreter
    Write-Information "* $( $interpreters.count ) script interpreters found."
    if ($interpreters.count -eq 0)
    {
        $ConfigContent
        return
    }
    $interpreters.keys|ForEach-Object {
        $key = $_
        $value = $interpreters[$_]
        if (Test-TomlKeyExist -ConfigContent $ConfigContent -Block "interpreter-aliases" -Key $key)
        {
            Write-Information ": $key already present in configuration."
        }
        else
        {
            $ConfigContent = Add-ToConfig -ConfigContent $configContent -Block "interpreter-aliases" -Line "$( $key ) = '$( $value )'"
        }
    }
    $configContent
}

# Update Tacoscript
function Install-Tacoupdate
{
    $Temp = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine')
    $tacoUpdate = $Temp + '\tacoupdate.zip'
    Set-Location $Temp
    if ((Out-String -InputObject (& 'C:\Program Files\tacoscript\bin\tacoscript.exe' --version)) -match "Version: (.*)")
    {
        $tacoVersion = $matches[1].trim()
        $tacoUpdateUrl = "https://downloads.openrport.io/tacoscript/$( $release )/?arch=Windows_x86_64&gt=$tacoVersion"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $tacoUpdateUrl -OutFile $tacoUpdate -UseBasicParsing
        If ((Get-Item tacoupdate.zip).length -eq 0)
        {
            Write-Output "* No Tacoscript update needed. You are on the latest $tacoVersion version."
            Remove-Item tacoupdate.zip -Force
            return
        }
        $dest = "C:\Program Files\tacoscript"
        Expand-Zip -Path $tacoUpdate -DestinationPath $dest
        Move-Item "$( $dest )\tacoscript.exe" "$( $dest )\bin" -Force
        Write-Output "* Tacoscript updated to $( (& "$( $dest )\bin\tacoscript.exe" --version) -match "Version" )"
        Remove-Item $tacoUpdate -Force|Out-Null
    }
}

# Install Tacoscript
function Install-Tacoscript
{
    $tacoDir = "C:\Program Files\tacoscript"
    $tacoBin = $tacoDir + '\bin\tacoscript.exe'
    if (Test-Path -Path $tacoBin)
    {
        Write-Output "* Tacoscript already installed to $( $tacoBin )"
        Install-Tacoupdate
        return
    }
    $Temp = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine')
    Set-Location $Temp
    $url = "https://download.openrport.io/tacoscript/$( $release )/?arch=Windows_x86_64"
    $file = $temp + "\tacoscript.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
    Write-Output "* Tacoscript dowloaded to $( $file )"
    New-Item -ItemType Directory -Force -Path "$( $tacoDir )"|Out-Null
    Expand-Zip -Path $file -DestinationPath $tacoDir
    New-Item -ItemType Directory -Force -Path "$( $tacoDir )\bin"|Out-Null
    Move-Item "$( $tacoDir )\tacoscript.exe" "$( $tacoDir )\bin\"
    $ENV:PATH = "$ENV:PATH;$( $tacoDir )\bin"

    [Environment]::SetEnvironmentVariable(
            "Path",
            [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";$( $tacoDir )\bin",
            [EnvironmentVariableTarget]::Machine
    )
    Write-Output "* Tacoscript installed to '$( $tacoDir )' $( (tacoscript.exe --version) -match "Version" )"
    Remove-Item $file -force
    # Create an uninstaller script for Tacoscript
    Set-Content -Path "$( $tacoDir )\uninstall.bat" -Value 'echo off
echo off
net session > NUL
IF %ERRORLEVEL% EQU 0 (
    ECHO You are Administrator. Fine ...
) ELSE (
    ECHO You are NOT Administrator. Exiting...
    PING -n 5 127.0.0.1 > NUL 2>&1
    EXIT /B 1
)
echo Removing Tacoscript now
ping -n 5 127.0.0.1 > null
rmdir /S /Q "%PROGRAMFILES%"\tacoscript\
echo Tacoscript removed
ping -n 2 127.0.0.1 > null
'
    Write-Output "* Tacoscript uninstaller created in $( $tacoDir )\uninstall.bat."
}

function Test-TomlKeyExist
{
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent,
        [Parameter(Mandatory)]
        [String]$Block,
        [Parameter(Mandatory)]
        [String]$Key
    )
    if (-not$ConfigContent -match [Regex]::Escape("^[$( $Block )]"))
    {
        $ConfigContent
        Write-Error "Block [$( $Block )] not found in config content"
        $false
        return
    }
    $inBlock = $false
    foreach ($Line in $ConfigContent -split "`n")
    {
        if ($Line -match "^\[$( $Block )\]")
        {
            $inBlock = $true
        }
        elseif ($Line -match "^\[.*\]")
        {
            $inBlock = $false
        }
        if ($inBlock -and ($line -match "$key = ") -and ($line -notmatch "#.*$key ="))
        {
            $true
            return
        }
    }
    $false
    return
}

function Set-TomlVar
{
    [OutputType([String])]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent,
        [Parameter(Mandatory)]
        [String]$Block,
        [Parameter(Mandatory)]
        [String]$Key,
        [Parameter(Mandatory)]
        [String]$Value
    )
    if (-not$ConfigContent -match [Regex]::Escape("^[$( $Block )]"))
    {
        Write-Error "Block [$( $Block )] not found in config content"
        $configContent
        return
    }
    $inBlock = $false
    $new = ""
    $ok = $false
    foreach ($Line in $configContent -split "`n")
    {
        if ($Line -match "^\[$( $Block )\]")
        {
            $inBlock = $true
        }
        elseif ($Line -match "^\[.*\]")
        {
            $inBlock = $false
        }
        if ($inBlock -and ($line -match "^([#, ])*$key = "))
        {
            $new = $new + "  $key = $value`n"
            $ok = $true
            $inBlock = $false
        }
        else
        {
            $new = $new + $line + "`n"
        }
    }
    if (-not$ok)
    {
        $e = @()
        $e += ": Key '$( $Key )' not found in config section [$( $Block )]."
        $e += ": Please add manually '$( $Key ) = `"$( $Value )`"'"
        Write-Error ($e -join "`n")
        return
    }
    if ( $PSCmdlet.ShouldProcess($ConfigContent))
    {
        Write-Debug $new
    }
    $new
    return
}

function Add-Netcard
{
    [OutputType([Object[]])]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent,
        [Parameter(Mandatory)]
        [CimInstance[]]$Interface,
        [Parameter(Mandatory)]
        [ValidateSet('net_lan', 'net_wan')]
        [String]$InterfaceType
    )
    if ($Interface.Length -gt 1)
    {
        Write-Information ""
        Write-Information "-----------------------::CAUTION::-----------------------"
        Write-Information ": You have more than one connected $( $InterfaceType ) card."
        Write-Information ": Just the first one will be activated for the monitoring."
        Write-Information ": Review the configuration file and adjust to your needs manually once the installation has finished."
        Write-Information ""
    }
    $InterfaceAlias = $Interface[0].InterfaceAlias
    $linkSpeed = ((Get-Netadapter|Where-Object Name -eq $InterfaceAlias)[0].LinkSpeed) -replace " Gbps", "000" -replace " Mbps", ""
    $linkSpeed = [math]::floor($linkSpeed);
    if (Test-TomlKeyExist -ConfigContent $ConfigContent -Block "monitoring" -Key $InterfaceType)
    {
        Write-Information "* Monitoring for $InterfaceType '$InterfaceAlias' already activated. Skipping."
        $ConfigContent
        return
    }
    try
    {
        $ConfigContent = Set-TomlVar -ConfigContent $ConfigContent -Block "monitoring" -Key $InterfaceType -Value "['$InterfaceAlias', '$linkSpeed']"
        Write-Information "* Monitoring for $InterfaceType '$InterfaceAlias' activated."
    }
    catch
    {
        Write-Information ": Monitoring for $InterfaceType '$InterfaceAlias' NOT activated."
        Write-Information $_
    }
    $ConfigContent
}

function Select-EnabledNetCard
{
    [OutputType([Object[]])]
    param (
        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [object[]]$NetAdapters
    )
    process
    {
        $filtered = @()
        foreach ($NetAdapter in $NetAdapters)
        {
            try
            {
                if ("Up" -eq (Get-NetAdapter -Name $NetAdapter.InterfaceAlias).Status)
                {
                    $filtered += $NetAdapter
                }
            }
            catch
            {
                Write-Information ": Failed to get status of $( $NetAdapter.InterfaceAlias ). Net Adapter ignored."
            }

        }
        $filtered
        return
    }
}

function Enable-Network-Monitoring
{
    [OutputType([Object[]])]
    param (
        [Parameter(Mandatory)]
        [Object[]]$ConfigContent
    )
    if ($ConfigContent -match "^\s*net_[lw]an")
    {
        Write-Information "* Network Monitoring already enabled."
        $ConfigContent
        return
    }
    try
    {
        $netLan = (Get-NetIPAddress|Where-Object IPAddress -Match "^(10|192.168|172.16)"|Select-EnabledNetCard)
        $netWan = (Get-NetIPAddress|Where-Object AddressFamily -eq "IPv4"|Where-Object IPAddress -NotMatch "^(10|192.168|172.16|127.|169.254.)"|Select-EnabledNetCard)
    }
    catch
    {
        Write-Information ": Getting list of Network adapters with 'Get-NetIPAddress' failed. Notwork monitoring not activated."
        $ConfigContent
        return
    }

    if (-Not$netLan -and -Not$netWan)
    {
        Write-Information "* No Lan cards detected. Check manually with 'Get-NetAdapter'"
        $ConfigContent
        return
    }
    if ($netLan)
    {
        $ConfigContent = Add-Netcard -ConfigContent $ConfigContent -Interface $netLan -InterfaceType 'net_lan'
    }
    if ($netWan)
    {
        $ConfigContent = Add-Netcard -ConfigContent $ConfigContent -Interface $netWan -InterfaceType 'net_wan'
    }
    $ConfigContent
}

function Get-HostUUID
{
    try
    {
        (Get-CimInstance -Class Win32_ComputerSystemProduct).UUID
        return
    }
    catch
    {
        Write-Information ": Reading system UUID with 'Get-CimInstance -Class Win32_ComputerSystemProduct' failed."
        Write-Information ": Falling back to a md5 hash of the computer name."
        $hash = [System.Security.Cryptography.HashAlgorithm]::Create("md5").ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($( $env:computername )))
        [System.BitConverter]::ToString($hash).Replace("-", "")
        return
    }
}

# Set the start type of the service
function Optimize-ServiceStartup
{
    param()
    #@formatter:off
    & sc.exe config rport start= delayed-auto
    & sc.exe failure rport reset= 0 actions= restart/5000
    #@formatter:on
}

function Invoke-Download
{
    Param(
        [Parameter()]
        [string]$gt = "0",
        [string]$pkgUrl
    )
    $Headers = @{ }
    if ($pkgUrl)
    {
        # Download from a custom URL given by global switch
        if ($pkgUrl -match ("^http.*windows_x86_64.zip"))
        {
            $downloadFile = "C:\Windows\temp\rport_Windows_x86_64.zip"
        }
        elseif ($pkgUrl -match ("^http.*windows_x86_64.msi"))
        {
            $downloadFile = "C:\Windows\temp\rport_Windows_x86_64.msi"
        }
        else
        {
            Write-Error "PkgUrl $( $pkgUrl ) is not a valid rport download url."
        }
        $url = $pkgUrl
        if ($env:RPORT_INSTALLER_DL_USERNAME -and $env:RPORT_INSTALLER_DL_PASSWORD)
        {
            $pair = "$( $env:RPORT_INSTALLER_DL_USERNAME ):$( $env:RPORT_INSTALLER_DL_PASSWORD )"
            $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
            $basicAuthValue = "Basic $encodedCreds"
            $Headers = @{
                Authorization = $basicAuthValue
            }
            Write-Information "* Downloading using HTTP basic auth"
        }
    }
    else
    {
        $downloadFile = "C:\Windows\temp\rport_$( $release )_Windows_x86_64.msi"
        $url = "https://downloads.openrport.io/rport/$( $release )/latest.php?filter=Windows_x86_64.msi&gt=$( $gt )"
    }

    if (Test-Path $downloadFile -PathType leaf)
    {
        Remove-Item $downloadFile -Force
    }
    Write-Information "* Downloading  $( $url )."
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $downloadFile -Headers $Headers
    return $downloadFile
}

# Create an uninstaller script for rport
function New-Uninstaller
{
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Set-Content -Path "$( $installDir )\uninstall.bat" -Value '
ECHO off
net session > NUL
IF %ERRORLEVEL% EQU 0 (
    ECHO You are Administrator. Fine ...
) ELSE (
    ECHO You are NOT Administrator. Exiting...
    PING -n 5 127.0.0.1 > NUL 2>&1
    EXIT /B 1
)
echo Removing rport now
ping -n 5 127.0.0.1 > null
sc stop rport
"%PROGRAMFILES%"\rport\rport.exe --service uninstall -c "%PROGRAMFILES%"\rport\rport.conf
cd C:\
rmdir /S /Q "%PROGRAMFILES%"\rport\
echo RPort removed
ping -n 2 127.0.0.1 > null
'
    Write-Output "* Uninstaller created in $( $installDir )\uninstall.bat."
}

function New-PSScriptFile
{
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string] $ScriptBlock
    )
    $ScriptBlock.Split("`n") | ForEach-Object {
        if ($_)
        {
            $_.Trim() | Out-File -FilePath $Path -Append
        }
    }
    $null = $Path
}

function Get-MSIVersionInfo
{
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.IO.FileInfo] $path
    )
    if (!(Test-Path $path.FullName))
    {
        throw "File '{0}' does not exist" -f $path.FullName
    }
    try
    {
        $WindowsInstaller = New-Object -com WindowsInstaller.Installer
        $Database = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $Null, $WindowsInstaller, @($path.FullName, 0))
        $Query = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
        $View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $Database, ($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null) | Out-Null
        $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
        $Version = $Record.GetType().InvokeMember("StringData", "GetProperty", $Null, $Record, 1)
        return $Version
    }
    catch
    {
        throw "Failed to get MSI file version: {0}." -f $_
    }
}
# END of templates/windows/functions.ps1 -----------------------------------------------------------------------------|


# BEGINNING of templates/windows/install.ps1 -------------------------------------------------------------------------|

$release = If ($t)
{
    "unstable"
}
Else
{
    "stable"
}
$myLocation = (Get-Location).path
$installDir = "$( $Env:Programfiles )\rport"
$dataDir = "$( $installDir )\data"

# Check if RPort is already installed
if (Test-Path $installDir)
{
    Write-Output "RPort is already installed."
    Write-Output "Download and execute the update script."
    Write-Output "Try the following:"
    Write-Output 'cd $env:temp
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url="https://pairing.openrport.io/update"
Invoke-WebRequest -Uri $url -OutFile "rport-update.ps1"
powershell -ExecutionPolicy Bypass -File .\rport-update.ps1
rm .\rport-update.ps1 -Force
'
    exit
}

# Test the connection to the RPort server first
$test_response = $null
try
{
    $test_response = (Invoke-WebRequest -Uri $connect_url -Method Head -TimeoutSec 2).BaseResponse
}
catch
{
    $status = [int]$_.Exception.Response.StatusCode
    if ($status -lt 500)
    {
        Write-Output "* Testing connection to $( $connect_url ) has succeeded."
    }
    else
    {
        $fc = $host.UI.RawUI.ForegroundColor
        $host.UI.RawUI.ForegroundColor = "red"
        $test_response
        Write-Output "# Testing connection to $( $connect_url ) has failed."
        $_.Exception.Message
        $host.UI.RawUI.ForegroundColor = $fc
        exit 1
    }
}
# Download the package from GitHub
$downloadFile = Invoke-Download -pkgUrl $pkgUrl
Write-Information "* Download finished and stored to $( $downloadFile )."
# Install
if ($downloadFile -match '\.zip$')
{
    Write-Output "* Installing from ZIP ..."
    # Create a directory
    mkdir $installDir| Out-Null
    mkdir $dataDir| Out-Null
    # Extract the ZIP file
    Expand-Zip -Path $downloadFile -DestinationPath $installDir
    # Create an uninstaller script
    New-Uninstaller
    $InstallMethod = 'zip'
}
elseif ($downloadFile -match '\.msi$')
{
    # Install the MSI
    Write-Output "* Installing MSI ..."
    $msiLog = "$( $downloadFile )-install.log"
    Start-Process msiexec.exe -Wait -ArgumentList "/i $( $downloadFile ) ARPSYSTEMCOMPONENT=1 ARPNOREMOVE=1 ARPNOMODIFY=1 ARPNOREPAIR=1 /qn /quiet /log $( $msiLog )"
    Write-Output "* MSI installed. Log saved to $( $msiLog )"
    $InstallMethod = 'msi'
}
else
{
    Write-Error "Unrecognized file extension for $( $downloadFile )"
}
Write-Output "* RPort installed via $InstallMethod"
$targetVersion = (& "$( $installDir )/rport.exe" --version) -replace "version ", ""
Write-Output "* RPort Client version $targetVersion installed."
$configFile = "$( $installDir )\rport.conf"

# Create a config file from the example
$configContent = Get-Content "$( $installDir )\rport.example.conf" -Encoding utf8
Write-Output "* Creating new configuration file $( $configFile )."
# Put variables into the config
$logFile = "$( $installDir )\rport.log"
$configContent = $configContent -replace 'server = .*', "server = `"$( $connect_url )`""
$configContent = $configContent -replace '.*auth = .*', "  auth = `"$( $client_id ):$( $password )`""
$configContent = $configContent -replace '#fingerprint = .*', "fingerprint = `"$( $fingerprint )`""
$configContent = $configContent -replace 'log_file = .*', "log_file = '$( $logFile )'"
$configContent = $configContent -replace '#data_dir = .*', "data_dir = '$( $dataDir )'"
# Set the system UUID
# For the time beeing creating the ID from the PowerShell is more reliable
$HostUUID = Get-HostUUID
$configContent = $configContent -replace '#id = .*', "id = `"$( $HostUUID )`""
$configContent = $configContent -replace 'use_system_id = true', 'use_system_id = false'
if ($x)
{
    # Enable commands and scripts
    $configContent = $configContent -replace '#allow = .*', "allow = ['.*']"
    $configContent = $configContent -replace '#deny = .*', "deny = []"
    $configContent = $configContent -replace '\[remote-scripts\]', "$&`n  enabled = true"
}
else
{
    # Disbale commands
    $configContent = Set-TomlVar -ConfigContent $configContent -Block "remote-commands" -Key "enabled" -Value "false"
}
# Enable/Disable file reception
$configContent = Enable-FileReception -ConfigContent $configContent -Switch $r
$attributes = @{
    'tags' = @()
    'labels' = @{}
}
# Get the location of the server
$geoUrl = "http://ip-api.com/json/?fields=status,country,city"
try
{
    $geoData = Invoke-RestMethod -Uri $geoUrl -TimeoutSec 5
    if ("success" -eq $geoData.status)
    {
        # Add geo data as tags
        $attributes.labels.country = $geoData.country
        $attributes.labels.city = $geoData.city
    }
}
catch
{
    Write-Output ": Fetching geodata failed. Skipping"
}

if ($g)
{
    # Add a custom tag
    $attributes.tags += $g
}

$OperatingSystem = Get-CIMInstance -Namespace 'Root\CIMv2' -ClassName 'Win32_OperatingSystem'

$attributes.tags += $client_id

Switch ($True)
    {
        {($OperatingSystem.Caption -imatch '(^.*Windows.*$)')}
            {
                $attributes.tags += 'Windows'
            }
        
        {($OperatingSystem.ProductType -in @(1))}
            {
                $attributes.tags += 'Workstations'
            }

        {($OperatingSystem.ProductType -in @(2))}
            {
                $attributes.tags += 'Servers'
            }

        {($OperatingSystem.ProductType -in @(3))}
            {
                $attributes.tags += 'Servers'
                $attributes.tags += 'Domain Controllers'
            }
    }

$attributes.tags += $OperatingSystem.OSArchitecture

$configContent = Set-TomlVar -ConfigContent $configContent `
  -Block "client" `
  -Key "attributes_file_path" `
  -Value "'C:\Program Files\rport\client_attributes.json'"
[IO.File]::WriteAllLines("C:\Program Files\rport\client_attributes.json", ($attributes|ConvertTo-Json))
$configContent = Enable-Network-Monitoring -ConfigContent $configContent
$configContent = Enable-InterpreterAlias -ConfigContent $configContent

# Finally, write the config to a file
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[IO.File]::WriteAllLines($configFile, $configContent, $Utf8NoBomEncoding)

if ($d)
{
    # in debug mode, exit here if
    Write-Output "Configuration written to $( $configFile )."
    Write-Output "==================================================================================="
    Get-Content $configFile -Raw
    Write-Output "==================================================================================="
    Write-Output "Exit! Service not installed."
    exit 0
}

if (-not(Get-Service rport -erroraction 'silentlycontinue'))
{
    # Register the service
    Write-Output ""
    Write-Output "* Registering rport as a windows service."
    & "$( $installDir )\rport.exe" --service install --config $configFile
    # Set the service startup and recovery actions
    Optimize-ServiceStartup
}
else
{
    Stop-Service -Name rport
}
Start-Service -Name rport
Get-Service rport

if ($i)
{
    try
    {
        Install-Tacoscript
    }
    catch
    {
        Write-Output ": Installation of Tacoscript failed"
        Write-Output $_
    }
}
# Clean Up
Remove-Item $downloadFile
if ($msiLog -And (Test-Path $msiLog))
{
    Remove-Item $msiLog -Force
}

function Finish
{
    Get-Log
    Set-Location $myLocation
    Write-Output "#
#
#  Installation of rport finished.
#
#  This client is now connected to $( $connect_url )
#
#  Look at $( $configFile ) and explore all options.
#  Logs are written to $( $installDir )/rport.log.
#
#  READ THE DOCS ON https://kb.openrport.io/
#
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#  Give us a star on https://github.com/openrport/openrport
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#
#

Thanks for using
   ____                   _____  _____           _
  / __ \                 |  __ \|  __ \         | |
 | |  | |_ __   ___ _ __ | |__) | |__) |__  _ __| |_
 | |  | | '_ \ / _ \ '_ \|  _  /|  ___/ _ \| '__| __|
 | |__| | |_) |  __/ | | | | \ \| |  | (_) | |  | |_
  \____/| .__/ \___|_| |_|_|  \_\_|   \___/|_|   \__|
        | |
        |_|
"
}

function Fail
{
    Get-Log
    Write-Output "
#
# -------------!!   ERROR  !!-------------
#
# Installation of rport finished with errors.
#

Try the following to investigate:
1) sc query rport

2) open C:\Program Files\rport\rport.log

3) READ THE DOCS on https://kb.rport.io

4) Request support on https://github.com/openrport/rport-pairing/discussions/categories/help-needed
"
}

if ($Null -eq (get-process "rport" -ea SilentlyContinue))
{
    Fail
}
else
{
    Finish
}
# END of templates/windows/install.ps1 -------------------------------------------------------------------------------|

