<#
.SYNOPSIS
  Enable Hyper-V kernel debug through either named-pipe serial debug or synthetic network debug.
.EXAMPLE
  WinUtilBelt-Enable-HyperVVMDebug.ps1 -VMName "My Hyper-V VM" -BCDAction
  # Dump BCD config.
.EXAMPLE
  WinUtilBelt-Enable-HyperVVMDebug.ps1 -VMName "My Hyper-V VM" -BCDAction -NoDebug
  # Turn off debug.
.EXAMPLE
  WinUtilBelt-Enable-HyperVVMDebug.ps1 -VMName "My Hyper-V VM" -BCDAction -SerialDebug -COM1NamedPipeName "vm-com1" -COM2NamedPipeName "vm-com2"
  # Named-pipe serial debug.
.EXAMPLE
  WinUtilBelt-Enable-HyperVVMDebug.ps1 -VMName "My Hyper-V VM" -BCDAction -SyntheticNetworkDebug -NetworkDebugPort 55555
  # Synthetic network debug; officially unsupported by MSFT.
.LINK
  # Enable named-pipe-based VM debug transport
  https://blogs.technet.microsoft.com/jhoward/2013/10/31/hyper-v-generation-2-virtual-machines-part-5/
.LINK
  # Enable synthetic-NIC-based VM debug transport
  http://withinrafael.com/how-to-set-up-synthetic-kernel-debugging-for-hyper-v-virtual-machines/
.PARAMETER VMName
  Hyper-V VM Name.
.PARAMETER VMVHDPath
  Path to VM's VHD that contains the System Partition; can be automatically inferred from VMName if VM only has 1 VHD.
.PARAMETER BCDAction
  The BCD on VM's System Partition will be located and acted upon.
.PARAMETER BCDCommands
  Extra bcdedit commands to be applied to VM's BCD.
.PARAMETER NoDebug
  Turn off debug.
.PARAMETER SerialDebug
  Enable serial debug.
.PARAMETER COM1NamedPipeName
  Named pipe name (e.g., "vm-com1"; NO "\\.\pipe\" prefix) that will be connected to VM's COM1 (for kernel debug).
.PARAMETER COM2NamedPipeName
  Named pipe name (e.g., "vm-com2"; NO "\\.\pipe\" prefix) that will be connected to VM's COM2 (for hypervisor debug).
.PARAMETER SyntheticNetworkDebug
  Enable synthetic network debug.
.PARAMETER NetworkDebugPort
  Network debug port for synthetic network debug.
.PARAMETER NetworkDebugKey
  Network debug key for synthetic network debug. Defaults to Wei's Intel start date. :)
#>

[CmdletBinding(
    SupportsShouldProcess=$True,
    DefaultParameterSetName="Dump"
)]
Param(

 [Parameter(Mandatory=$True)]
 [String]
 $VMName,

 [Parameter()]
 [String]
 $VMVHDPath,

 [Parameter()]
 [switch]
 $BCDAction,

 [Parameter()]
 [String[]]
 $BCDCommands=@("/enum", "/dbgsettings", "/hypervisorsettings"),

 [Parameter(
     Mandatory=$True,
     ParameterSetName="NoDebug"
     )]
 [Switch]
 $NoDebug,

 [Parameter(
     Mandatory=$True,
     ParameterSetName="SerialDebug"
     )]
 [Switch]
 $SerialDebug,

 [Parameter(
     ParameterSetName="SerialDebug"
     )]
 [ValidateNotNullOrEmpty()]
 [String]
 $COM1NamedPipeName="vm-com1",

 [Parameter(
     ParameterSetName="SerialDebug"
     )]
 [ValidateNotNullOrEmpty()]
 [String]
 $COM2NamedPipeName="vm-com2",

 [Parameter(
     Mandatory=$True,
     ParameterSetName="SyntheticNetworkDebug"
     )]
 [Switch]
 $SyntheticNetworkDebug,

 [Parameter(
     ParameterSetName="SyntheticNetworkDebug"
     )]
 [String]
 $NetworkDebugPort="51234",

 [Parameter(
     ParameterSetName="SyntheticNetworkDebug"
     )]
 [String]
 $NetworkDebugKey="20.15.06.08"

)

$bcdedit=(Get-Command bcdedit).Path

& {
    $VM=Get-VM -Name "$VMName"
    if (-not $VM) {
        Throw "Cannot find VM $VMName."
    }
    if ($VM.State -ne "Off") {
        Throw "$VMName needs to be turned off to proceed."
    }
}

$BCDPath=$NULL

if ($BCDAction) {

    if (-not $VMVHDPath) {
        # infer VHD path
        $hd=@($(Get-VM -Name "$VMName").harddrives)
        foreach ($d in $hd) {
            Write-Verbose "$VMName has a hard drive at: $($d.path)"
        }
        if ($hd.length > 1) {
            Throw "Do not know which of $VMName's drives contains the System Partition."
        }
        $VMVHDPath=$hd.path
        Write-Verbose "Inferred VHD Path for `"$VMName`": $VMVHDPath"
    }

    if (-not $(Get-VHD -Path "$VMVHDPath").Attached) {
        Mount-VHD -Path "$VMVHDPath"
        Write-Verbose "$VMVHDPath mounted."
    }

    $syspart=$(Get-DiskImage -ImagePath "$VMVHDPath" | Get-Disk | Get-Partition | ? {$_.type -eq 'System'} | Select-Object -First 1)
    if (-not $syspart) {
        Throw "$VMVHDPath does not contain System Partition."
    }

    $driveletter=$NULL
    if (-not $syspart.DriveLetter) {
        # http://stackoverflow.com/a/12488560
        # http://www.powershellmagazine.com/2012/01/12/find-an-unused-drive-letter/
        function get-freedriveletters () {
            $([int][char]'D') .. $([int][char]'Z') | % { [char]$_ } | ? { Get-PSDrive -Scope Global -Name $_ > $null 2>&1; !$? }
        }

        $freedriveletters=get-freedriveletters
        $driveletter=$($freedriveletters | Get-Random)
        Write-Verbose "A free drive letter: $driveletter."
        Set-Partition -InputObject $syspart -NewDriveLetter $driveletter
    } else {
        $driveletter=$syspart.DriveLetter
    }

    if (-not $driveletter) {
        Throw "Cannot access $VMVHDPath's System Partition through a drive letter."
    }
    Write-Verbose "$VMVHDPath's System Partition is mounted on Drive $driveletter."
    $BCDPath="${driveletter}:\EFI\Microsoft\Boot\BCD"
    Write-Verbose "$VMName's BCD is accessible from: $BCDPath."

}

function run-bcdcommands ($BCDPath, $BCDCommands) {
    if (Test-Path $BCDPath) {
        $BCDCommands | % {
            $exp="$bcdedit /store '$BCDPath' $_"
            Write-Verbose $exp
            Invoke-Expression $exp
        }
    }
}

if ($SerialDebug) {
    if ($BCDPath) {
        run-bcdcommands $BCDPath @(
            "/set '{bootmgr}' timeout 5",
            "/set '{default}' testsigning on",
            "/set '{default}' nointegritychecks on",
            "/set '{default}' bootmenupolicy legacy",
            "/set '{default}' debug on",
            "/set '{default}' bootdebug on",
            "/dbgsettings serial debugport:1 baudrate:115200",
            "/set '{default}' hypervisordebug on",
            "/hypervisorsettings serial debugport:2 baudrate:115200"
        )
        run-bcdcommands $BCDPath $BCDCommands
    }
    & {
        Set-VMFirmware -VMName "$VMName" -EnableSecureBoot Off
        Write-Verbose "Secure boot on $VMName is turned off."
        $NamedPipe="\\.\pipe\$COM1NamedPipeName"
        Set-VMComPort -VMName "$VMName" -Number 1 -Path "$NamedPipe"
        Write-Verbose "$VMName COM1 => $NamedPipe"
        Write-Verbose "windbg -k com:pipe,port=$NamedPipe,reconnect -v"
        $NamedPipe="\\.\pipe\$COM2NamedPipeName"
        Set-VMComPort -VMName "$VMName" -Number 2 -Path "$NamedPipe"
        Write-Verbose "$VMName COM2 => $NamedPipe"
        Write-Verbose "windbg -k com:pipe,port=$NamedPipe,reconnect -v"
    }
} elseif ($SyntheticNetworkDebug) {
    if ($BCDPath) {
        run-bcdcommands $BCDPath @(
            "/set '{bootmgr}' timeout 5",
            "/set '{default}' testsigning on",
            "/set '{default}' nointegritychecks on",
            "/set '{default}' bootmenupolicy legacy",
            "/set '{default}' debug on",
            "/set '{default}' bootdebug on",
            # hostip and port are ignored in synthetic network debug
            "/dbgsettings net hostip:1.2.3.4 port:55555 key:$NetworkDebugKey"
        )
        run-bcdcommands $BCDPath $BCDCommands
    }
    & {
        Set-VMFirmware -VMName "$VMName" -EnableSecureBoot Off

        $MgmtSvc=Get-WmiObject -Class "Msvm_VirtualSystemManagementService" -Namespace "root\virtualization\v2"

        $VM=Get-VM -VMName $VMName
        $Data=Get-WmiObject -Namespace "root\virtualization\v2"  -class "Msvm_VirtualSystemSettingData" | ? ConfigurationID -eq $VM.Id

        $Data.DebugPort=$NetworkDebugPort
        $Data.DebugPortEnabled=1

        $MgmtSvc.ModifySystemSettings($Data.GetText(1))

        Write-Verbose "windbg -k net:target=127.0.0.1,port=$NetworkDebugPort,key=$NetworkDebugKey"
        Write-Verbose "!!! $VMName needs to be power-cycled (not only reset) for synthetic debug to work!"
    }

} elseif ($NoDebug) {
    if ($BCDPath) {
        run-bcdcommands $BCDPath @(
            "/set '{bootmgr}' timeout 5",
            "/set '{default}' testsigning off",
            "/set '{default}' nointegritychecks off",
            "/set '{default}' bootmenupolicy standard",
            "/set '{default}' debug off",
            "/set '{default}' bootdebug off",
            "/set '{default}' hypervisordebug off"
        )
        run-bcdcommands $BCDPath $BCDCommands
    }
    & {
        #Set-VMFirmware -VMName "$VMName" -EnableSecureBoot On

        $MgmtSvc=Get-WmiObject -Class "Msvm_VirtualSystemManagementService" -Namespace "root\virtualization\v2"

        $VM=Get-VM -VMName $VMName
        $Data=Get-WmiObject -Namespace "root\virtualization\v2"  -class "Msvm_VirtualSystemSettingData" | ? ConfigurationID -eq $VM.Id

        $Data.DebugPortEnabled=0

        $MgmtSvc.ModifySystemSettings($Data.GetText(1))
    }
} else { # Dump BCD config.
    if ($BCDPath) {
        run-bcdcommands $BCDPath $BCDCommands
    }
    Get-VMComPort -VMName "$VMName" -Number 1
    Get-VMComPort -VMName "$VMName" -Number 2
    & {
        $MgmtSvc=Get-WmiObject -Class "Msvm_VirtualSystemManagementService" -Namespace "root\virtualization\v2"

        $VM=Get-VM -VMName $VMName
        $Data=Get-WmiObject -Namespace "root\virtualization\v2"  -class "Msvm_VirtualSystemSettingData" | ? ConfigurationID -eq $VM.Id

        Write-Host "NetworkDebugPort: $($Data.DebugPort)"
        Write-Host "NetworkDebugPort: $($Data.DebugPortEnabled)"
    }
}

if ($VMVHDPath -and $(Get-VHD -Path "$VMVHDPath").Attached) {
    Dismount-VHD -Path "$VMVHDPath"
    Write-Verbose "$VMVHDPath dismounted."
}