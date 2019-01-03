[CmdletBinding(
    SupportsShouldProcess=$True
)]
param(
    [Parameter(
        Mandatory=$True
    )]
    [ValidateScript(
        {
            Test-Path -Path $_ -PathType Leaf
        }
    )]
    $Blg,

    [String]
    $ExtraRelogOptions,

    $NumThreads=((Get-WmiObject -class win32_processor).NumberOfLogicalProcessors * 3),

    [Switch]
    $OverwriteRelogCsv,

    [Switch]
    $OverwriteUtcCsv,

    [Switch]
    $OverwriteUtcPivotCsv

)

Set-StrictMode -Version Latest

. $PSScriptRoot\lib\Invoke-Parallel.ps1

$Blg=Get-Item $Blg
$blgbname = $Blg.BaseName
$blgfname = $Blg.FullName
$blgdir = $Blg.DirectoryName

$relogcsv = [IO.Path]::Combine($blgdir, "${blgbname}_relog.csv")

if (!(Test-Path $relogcsv -PathType Leaf) -or $OverwriteRelogCsv) {
    Invoke-Expression @"
relog.exe "$blgfname" $ExtraRelogOptions -f CSV -o "$relogcsv"
"@
}

if (!(Test-Path $relogcsv -PathType Leaf)) {
    throw "Fail to create $relogcsv"
}

$lines=[String[]][IO.File]::ReadAllLines($relogcsv)

$hline=$lines[0]
$headers=$hline -split ','
$header0=$headers[0]
$headers=$headers[1..($headers.Length-1)]

$lines=$lines[1..($lines.Length-1)]

$pat_timezone=[regex] @"
(?x)
\(
    ([^)]+)
(?<=Time)\)
"@

$m = [Regex]::Match($header0, $pat_timezone)
if ($m.Success) {
    $timezone = $m.Groups[1].Value
    $timezoneinfo = [TimeZoneInfo]::FindSystemTimeZoneById($timezone)
}

<#
Produce UTC CSV.
#>

$utccsv = [IO.Path]::Combine($blgdir, "${blgbname}_utc.csv")

if (!(Test-Path $utccsv -PathType Leaf) -or $OverwriteUtcCsv) {
    New-Item $utccsv -Force -ItemType File | Out-Null

    $nlines = $lines.Length
    $output = [Object[]]::new(1 + $nlines) # 1 is for the header row.

    $output[0] = (@($header0 -replace $timezone, "Universal Time Coordinated") + $headers) -join ","

    1..$NumThreads | Invoke-Parallel -ImportVariables -ScriptBlock {
        $index = $_ - 1
        while ($index -lt $nlines) {
            $line = $lines[$index]
            $fields = $line -split ','
            $output[ 1 + $index] += (
                (@("`"$(
                [System.TimeZoneInfo]::ConvertTimeToUtc(
                    [DateTime]($fields[0] -replace '"', ''),
                    $timezoneinfo
                    ).ToString("MM/dd/yyyy HH:mm:ss.fff")
                )`"") + $fields[1..($fields.Length - 1)]
                ) -join ","
            )
            $index += $NumThreads
        }
    }

    [IO.File]::WriteAllLines($utccsv, $output)
}


<#
Produce UTC Pivot-able CSV.
#>

$header_fields = @(
    "Host",
    "CounterGroup",
    "CounterObject"
    )

$utcpivotcsv = [IO.Path]::Combine($blgdir, "${blgbname}_utc_pivot.csv")

if (!(Test-Path $utcpivotcsv -PathType Leaf) -or $OverwriteUtcPivotCsv) {

    New-Item $utcpivotcsv -Force -ItemType File | Out-Null

    # $output can be used here because it has been previously converted to UTC timestamp
    $hline = $output[0]
    $headers = $hline -split ','
    $ncounters = $headers.Length - 1 # 1 is the timestamp column

    # header0 is always "UTC timestamp"
    $pat_header = [regex] @"
(?x)
\\\\(?<Host>[^\\]*)
\\(?<CounterGroup>[^\\]*)
\\(?<CounterObject>[^\\"]*)
"@
    $headers = $headers[1..($headers.Length - 1)] | % {
        $m = [regex]::Match($_, $pat_header)
        $hash = @{}
        if ($m.Success) {
            foreach ($f in $header_fields) {
                $hash[$f] = $m.Groups[$f].Value
            }
        }
        $hash
    }
    $headers_csvtext = $headers | % {
        $hash = $_
        @($header_fields | % { "`"$($hash[$_])`""}) -join ","
    }

    $lines = $output[1..($output.Length - 1)]

    $output = [Object[]]::new(1 + $lines.Length*$ncounters) # 1 is for the header row.
    $output[0] = (
        (@('UtcTimestap') + $header_fields + @('CounterValue')) | % { "`"$_`""}
    ) -join ","

    0..($ncounters-1) | Invoke-Parallel -ImportVariables -ScriptBlock {
        $index = $_
        $htext = $headers_csvtext[$index]
        foreach ($i in 0..($lines.Length-1)) {
            $line = $lines[$i]
            $fields = $line -split ','
            $tstamp = $fields[0]
            $value = $fields[$index+1]
            $output[1 + $i*$ncounters + $index] = @(
                $tstamp, $htext, $value
            ) -join ","
        }
    }

    [IO.File]::WriteAllLines($utcpivotcsv, $output)

}