<#
.SYNOPSIS
    Converte il report JaCoCo prodotto da Pester nel formato "Generic Test Coverage" di SonarCloud.

.EXAMPLE
    ./.github/scripts/Convert-CoverageToSonar.ps1 -JaCoCoPath coverage/jacoco.xml -OutputPath coverage/sonar-coverage.xml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JaCoCoPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settings = [System.Xml.XmlReaderSettings]::new()
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
$settings.XmlResolver = $null
$reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $JaCoCoPath).Path, $settings)
try {
    $report = [System.Xml.XmlDocument]::new()
    $report.XmlResolver = $null
    $report.Load($reader)
}
finally {
    $reader.Dispose()
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<coverage version="1">')
foreach ($package in $report.SelectNodes('//package')) {
    foreach ($source in $package.SelectNodes('sourcefile')) {
        $path = '{0}/{1}' -f $package.GetAttribute('name'), $source.GetAttribute('name')
        [void]$sb.AppendLine(('  <file path="{0}">' -f [System.Security.SecurityElement]::Escape($path)))
        foreach ($line in $source.SelectNodes('line')) {
            $covered = if ([int]$line.GetAttribute('ci') -gt 0) { 'true' } else { 'false' }
            [void]$sb.AppendLine(('    <lineToCover lineNumber="{0}" covered="{1}"/>' -f $line.GetAttribute('nr'), $covered))
        }
        [void]$sb.AppendLine('  </file>')
    }
}
[void]$sb.AppendLine('</coverage>')

$dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Output "Scritto $OutputPath"
