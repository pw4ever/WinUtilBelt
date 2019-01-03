<#
.SYNOPSIS
  Extract a stand-alone set of Windows Kit tools from ISO.
#>

[CmdletBinding(
    SupportsShouldProcess = $True
)]
param(

    [Parameter(Mandatory = $true)]
    [ValidateScript({
        Test-Path $_ -PathType Leaf
    })]
    $ISO,

    [Parameter(Mandatory = $true)]
    [ValidateScript({
        (!(Test-Path -Path $_ -PathType Leaf)) -and `
        $(
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Test-Path -Path $_ -PathType Container
            )
    })]
    $TargetPath,

    [Parameter()]
    [ValidateSet("SDK", "WDK")]
    $KitType="SDK",

    [Parameter()]
    $Installers=@{
        "SDK" = @(
            "Installers\WPTx64-x86_en-us.msi",
            "Installers\X64 Debuggers And Tools-x64_en-us.msi",
            "Installers\Windows SDK Signing Tools-x86_en-us.msi",
            $NULL
            );
        "WDK" = @(
            "Installers\Test Authoring and Execution Framework x64-x64_en-us.msi",
            "Installers\WDK Test Target Setup x64-x64_en-us.msi",
            "Installers\Windows Driver Kit Binaries-x86_en-us.msi",
            "Installers\Windows Driver Kit Headers and Libs-x86_en-us.msi",
            "Installers\Windows Driver Framework Headers and Libs-x86_en-us.msi",
            "Installers\Windows Driver Kit-x86_en-us.msi",
            "Installers\Windows Debugging WDK Integration-x86_en-us.msi",
            $NULL
        );
    },

    # exist solely to allow reshuffle previous options
    $_DummyOption
)

Set-StrictMode -Version Latest

$Installers = $Installers[$KitType]

function main {

    [Boolean]$mountp = $False
    try {
        $disk = Mount-DiskImage -ImagePath $ISO
        $mountp = $True
        $drive = ($disk | Get-Volume).DriveLetter
        if ([String]::IsNullOrWhiteSpace($drive)) {
            throw "Cannot identify the drive letter of the mounted ISO file $ISO."
        }
        Write-Verbose "$ISO is mounted on drive ${drive}:."

        $Installers | ? { ![String]::IsNullOrWhiteSpace($_) } | % {
            $path=[IO.Path]::Combine("${drive}:\", $_)
            # N.B. -Wait is critical: Block
            Start-Process -FilePath msiexec.exe -Wait -ArgumentList @(
                "/qb",
                "TARGETDIR=`"$TargetPath`"",
                "/a",
                "`"$path`""
            )
            Write-Verbose "$path installed to $TargetPath."
        }
    }
    finally {
        if ($mountp) {
            Dismount-DiskImage -ImagePath $ISO | Out-Null
            Write-Verbose "$ISO is dismounted."
        }
    }

}

main