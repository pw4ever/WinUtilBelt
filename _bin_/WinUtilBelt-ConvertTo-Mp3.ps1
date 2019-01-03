<#
.SYNOPSIS
  Convert the source file to MP3 using FFmpeg.
.EXAMPLE
  ls -File -Recurse *.mp4 | WinUtilBelt-ConvertTo-Mp3 -Path $_ -Verbose
.EXAMPLE
  # Invoke-Parallel is recommended for speeding up the conversion in parallel.
  # https://github.com/RamblingCookieMonster/Invoke-Parallel
  ls -File -Recurse *.mp4 | % { $_.FullName } | Invoke-Parallel -ScriptBlock { WinUtilBelt-ConvertTo-Mp3 -Path $_ -Verbose }
.PARAMETER Path
  Path of the source file.
.PARAMETER FFmpegOptions
  Global options for FFmpeg.
.PARAMETER FFmpegInfileOptions
  Input file options for FFmpeg.
.PARAMETER FFmpegOutfileOptions
  Output file options for FFmpeg; default to 48k for audiobook quality with small file size.
.PARAMETER OutfileDirectorySuffix
  Outfile directory suffix; see help for $OutfileInSameDirectory.
.PARAMETER OutfileInSameDirectory
  Default to create the outfile in a subfolder taking the name after the infile's folder name suffixed with $OutfileDirectorySuffix; this option override this behavior.
.PARAMETER FFmpegExe
  Name of the FFmpeg executable.
#>

[CmdletBinding(
  SupportsShouldProcess = $True
)]
Param(

  [Parameter(
    ValueFromPipeline = $True,
    ValueFromPipelineByPropertyName = $True
  )]
  [ValidateScript({
    Test-Path $_
  })]
  [IO.FileInfo]
  $Path,

  [Parameter()]
  $FFmpegOptions = "-loglevel panic -hide_banner",

  [Parameter()]
  $FFmpegInfileOptions,

  [Parameter()]
  $FFmpegOutfileOptions = "-map 0:a:0 -b:a 48k",

  [Parameter()]
  $OutfileDirectorySuffix = "_mp3",

  [Parameter()]
  [Switch]
  $OutfileInSameDirectory,

  [Parameter()]
  [ValidateScript({
    Get-Command $_
  })]
  $FFmpegExe = "ffmpeg.exe"

)

Process {
  $dir = ([IO.FileInfo]$Path).Directory
  $pdirname = $dir.Name.Trim([IO.Path]::GetInvalidFileNameChars())
  $name = $Path.Name
  $bname = $Path.BaseName

  Push-Location $dir -ErrorAction Stop

  $cmd=@"
& "$FFmpegExe" $FFmpegOptions $FFmpegInfileOptions -i "$name" $FFmpegOutfileOptions "$(
  if (!$OutfileInSameDirectory) {
    $d="${pdirname}${OutfileDirectorySuffix}"
    New-Item -Path "$d" -ItemType Directory -Force >$NULL 2>&1
    if($?) {
      "$d/"
    }
  }
  )$bname.mp3"
"@

  Write-Verbose $cmd # for debug
  Invoke-Expression $cmd

  Pop-Location
}