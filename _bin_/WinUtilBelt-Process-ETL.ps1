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
    $Etl,

    $EtlTimezone,

    $NumThreads=((Get-WmiObject -class win32_processor).NumberOfLogicalProcessors * 3),

    [Switch]
    $OverwriteTraceFmt,

    [Switch]
    $OverwriteCsv

)

Set-StrictMode -Version Latest

. $PSScriptRoot\lib\Invoke-Parallel.ps1

$Etl=Get-Item $Etl
$etlbname=$Etl.BaseName
$etlfname=$Etl.FullName
$etldir=$Etl.DirectoryName
$tracefmtout=[IO.Path]::Combine($etldir, "_$etlbname.txt")
$csv=[IO.Path]::Combine($etldir, "$etlbname.csv")

if (![String]::IsNullOrWhiteSpace($EtlTimezone)) {
    $timezoneinfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($EtlTimezone)
    if ([String]::IsNullOrWhiteSpace($timezoneinfo)) {
        throw "$EtlTimezone is not a valid time zone parsable by [TimeZoneInfo]::FindSystemTimZoneById()."
    }
}

if (!(Test-Path $tracefmtout -PathType Leaf) -or $OverwriteTraceFmt) {
    tracefmt.exe "$etlfname" -o "$tracefmtout" 2>&1 | Out-Null
}

if ((Test-Path $csv -PathType Leaf) -and !$OverwriteCsv) {
    Write-Verbose "$csv already exists; use -OverwriteCsv to overwrite."
    return 1
}

$lines=[IO.File]::ReadAllLines($tracefmtout)

$pat_timestamp=[regex] '(?x)::(\d{2}/\d{2}/\d{4})-(\d{2}:\d{2}:\d{2}.\d{0,3})\s'
$pat_fieldpair=[regex] '(?x)"([^"]+)":"?([^"]+)"?[,}]'

$fields=@{} # get fields
$results=[object[]]::new($lines.Length)

$nlines = $lines.Length
$timestamp_keyname = "Timestamp"
1..$NumThreads | Invoke-Parallel -ImportVariables -ScriptBlock {
    $index = $_ - 1

    while ($index -lt $nlines) {
        $line = $lines[$index]
        $lresult=@{} # line result
        $m=[Regex]::Match($line, $pat_timestamp)
        if ($m.Success) {
            $header = $timestamp_keyname; $lresult[$header] = "$($m.Groups[1].Value) $($m.Groups[2].Value)"; $fields[$header]++
            if (![String]::IsNullOrWhiteSpace($timezoneinfo)) { # convert to UTC if $EtlTimezone is specified
                $lresult[$header] = [TimeZoneInfo]::ConvertTimeToUtc(
                    [DateTime]$lresult[$header],
                    $timezoneinfo
                ).ToString("MM/dd/yyyy HH:mm:ss.fff")
            }
        }
        $ms=[Regex]::Matches($line, $pat_fieldpair)
        foreach ($m in $ms) {
            if ($m.Success) {
                $header=$m.Groups[1].Value; $lresult[$header]=$m.Groups[2].Value; $fields[$header]++
            }
        }
        $results[$index] = $lresult
        $index += $NumThreads
    }
}

$headers=@($timestamp_keyname) + @($fields.Keys | ? { ! $timestamp_keyname.Equals($_) } | Sort-Object)

$finalresult = @(($headers | % { "`"$_`""}) -join ",") + @(
    foreach ($result in $results) {
        ($headers | % { "`"$($result[$_])`"" }) -join ","
    }
)

[IO.File]::WriteAllLines(
    $csv,
    $finalresult
)