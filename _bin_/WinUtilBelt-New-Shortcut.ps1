<#
.SYNOPSIS
  Create a new shortcut (.lnk file).
.EXAMPLE
  WinUtilBelt-New-Shortcut.ps1 -Shortcut $env:USERPROFILE\Desktop\app.lnk -Target c:\bin\app.exe -Argument "arg1 arg2" -Hotkey "CTRL+ALT+A"
.PARAMETER Shortcut
  Path to the shortcut file to be created.
.PARAMETER Target
  Path to the target.
.PARAMETER Argument
  All arguments to target in one string.
.PARAMETER Hotkey
  Hotkey to access the shortcut; single letters will be converted: <x> => CTRL+ALT+<x>.
.PARAMETER WorkDir
  Working directory of the shortcut.
.PARAMETER Admin
  Create an Admin shortcut.
#>

[CmdletBinding(
SupportsShouldProcess=$True,
PositionalBinding=$False

)]
param(

    [Parameter(
	 Mandatory=$True
    )]
    [String]
    $Shortcut,

    [Parameter(
     Mandatory=$True
    )]
    [String]
    $Target,

    [Parameter(
    )]
    [String]
    $Argument,

    [Parameter(
    )]
    [String]
    $Hotkey,

    [Parameter(
    )]
    [String]
    $WorkDir,

    [Parameter(
    )]
    [Switch]
    $Admin

)

function new-shortcut ([String]$shortcut,
					   [String]$target,
					   [String]$argument,
					   [String]$hotkey,
					   [String]$workdir,
                       [Bool]$admin)
{
    # http://stackoverflow.com/a/9701907
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($shortcut)
    $s.TargetPath = $target
    if (![String]::IsNullOrEmpty($argument)) {
        $s.Arguments = $argument
    }
    if (![String]::IsNullOrEmpty($hotkey)) {
        if ($hotkey.Length -eq 1) {
            $hotkey = "CTRL+ALT+" + $hotkey
        }
        $s.HotKey = $hotkey
    }
    if (![String]::IsNullOrEmpty($workdir)) {
        $s.WorkingDirectory = $workdir
    }
    $s.Save()

    if ($admin) {
        # hack: https://blogs.msdn.microsoft.com/abhinaba/2013/04/02/c-code-for-creating-shortcuts-with-admin-privilege/
        $fs=New-Object IO.FileStream -ArgumentList $shortcut, ([IO.FileMode]::Open), ([IO.FileAccess]::ReadWrite)
        try {
            $fs.Seek(21, [IO.SeekOrigin]::Begin) | Out-Null
            $fs.WriteByte(0x22) | Out-Null
        }
        finally {
            $fs.Dispose() | Out-Null
        }
    }
}

# Shortcut needs to be absolute.
if (![System.IO.Path]::IsPathRooted($Shortcut)) {
    $Shortcut=[System.IO.Path]::GetFullPath([System.IO.Path]::Combine($pwd.Path, $Shortcut))
}

new-shortcut $Shortcut $Target $Argument $Hotkey $WorkDir $Admin
