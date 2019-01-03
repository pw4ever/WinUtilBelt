<#
.SYNOPSIS
  Enable KDNet debug transport.
.EXAMPLE
  WinUtilBelt-Enable-KDNet -hostip 192.168.1.2 -bdf 1.0.1 -id '{current}' -debughv -osport 50000 -hvport 50001 -key 1.2.3.4
.PARAMETER hostip
  IP address of the KD debug host.
.PARAMETER bdf
  PCI Bus/Device/Function (BDF) specifier to the net card on the KD debug target to be used as the KDNet transport.
.PARAMETER id
  ID of BCD entry to be changed.
.PARAMETER debughv
  Enable Hyper-V (HV) debug.
.PARAMETER osport
  TCP port number to be used for OS debug.
.PARAMETER hvport
  TCP port number to be used for Hyper-V debug.
.PARAMETER key
  KDNet key.
#>

[CmdletBinding(
    SupportsShouldProcess = $True
)]
Param(
    [String]$hostip,

    [Parameter()]
    [String]$bdf = $(
        Get-NetAdapter | ? { $_.Status -match 'up' } | ? { $_.MediaType -match '802.3' } | `
            ? { Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction SilentlyContinue } | `
            Select-Object -First 1 | Get-NetAdapterHardwareInfo -ErrorAction SilentlyContinue | `
            % { "$($_.Bus).$($_.Device).$($_.Function)" }
    ),

    [Parameter()]
    [String]$id = "{default}",

    [Parameter()]
    [switch]
    $debughv,

    [Parameter()]
    [Int32]$osport = 50000,

    [Parameter()]
    [Int32]$hvport = 50001,

    [Parameter()]
    [String]$key = "1.2.3.4"
)

# List available Ethernet adapters
Write-Host 'Available network adapters.'
Get-NetAdapter | ? { Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction SilentlyContinue } | `
    ft -Property `
@{label = "BDF"; expression = { $hw = Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction SilentlyContinue; "$($hw.bus).$($hw.device).$($hw.function)" }},
Status, Name,
@{label = "IPv4"; expression = { (Get-NetIPAddress -InterfaceAlias $_.Name -AddressFamily ipv4 ).IPAddress }},
ifDesc

if ([String]::IsNullOrWhiteSpace($hostip) -or [String]::IsNullOrWhiteSpace($bdf)) {
    return
}

if ($bdf -notmatch "(?i)^[0-9a-f]{1,3}\.[0-9a-f]{1,3}\.[0-9a-f]{1,3}" ) {
    throw 'Invalid -bdf.'
}

Write-Host "Selected BDF: $bdf.`n"

$bcdedit = (Get-Command bcdedit).Path

@(
    "$bcdedit /set '$id' testsigning on"
    "$bcdedit /set '$id' nointegritychecks on"
    "$bcdedit /set '$id' bootmenupolicy legacy"
    "$bcdedit /set '$id' bootstatuspolicy IgnoreAllFailures"
    "$bcdedit /set '$id' loadoptions DDISABLE_INTEGRITY_CHECKS"
    "$bcdedit /set '$id' sos on"
    "$bcdedit /set '{bootmgr}' timeout 5"
    #"$bcdedit /set '$id' recoveryenabled no"
    "$bcdedit /debug '$id' on"
    "$bcdedit /bootdebug '$id' on"
    "$bcdedit /dbgsettings net hostip:$hostip port:$osport key:$key"
    "$bcdedit /set '{dbgsettings}' busparams $bdf"
) | % { if ($_) { Write-Host $_; Invoke-Expression $_ } }

if ($debughv) {
    Write-Verbose "Enabling Hyper-V"
    $(Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V `
      -All -Online -ErrorVariable err -ErrorAction SilentlyContinue;
      !$err) -or `
    $(Add-WindowsFeature -Name Hyper-V `
      -ErrorVariable err -ErrorAction SilentlyContinue; !$err)

    @(
        "$bcdedit /set '$id' hypervisordebug on"
        "$bcdedit /set '$id' hypervisorlaunchtype auto"
        "$bcdedit /hypervisorsettings net hostip:$hostip port:$hvport key:$key"
        "$bcdedit /set '{hypervisorsettings}' hypervisorbusparams $bdf"
    ) | % { if ($_) { Write-Host $_; Invoke-Expression $_ } }
}
