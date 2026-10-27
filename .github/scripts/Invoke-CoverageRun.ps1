<#
.SYNOPSIS
    Esegue la suite Pester con misura della copertura e produce il report per SonarCloud.

.DESCRIPTION
    Scrive coverage/jacoco.xml, coverage/testresults.xml e coverage/sonar-coverage.xml.
    Termina con errore se un test fallisce o se la copertura dei due script scende sotto il minimo.
#>
[CmdletBinding()]
param(
    [double]$MinimumCoverage = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $repoRoot
try {
    Import-Module Pester -MinimumVersion 5.0.0

    $config = New-PesterConfiguration
    $config.Run.Path = 'tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @('scripts/Validate-Links.ps1', 'scripts/Verify-IsoIntegrity.ps1')
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = 'coverage/jacoco.xml'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'JUnitXml'
    $config.TestResult.OutputPath = 'coverage/testresults.xml'

    $result = Invoke-Pester -Configuration $config

    & (Join-Path $repoRoot '.github/scripts/Convert-CoverageToSonar.ps1') -JaCoCoPath 'coverage/jacoco.xml' -OutputPath 'coverage/sonar-coverage.xml'

    $coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
    Write-Output "Copertura: $coverage% (minimo $MinimumCoverage%), test falliti: $($result.FailedCount)"
    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) test falliti." }
    if ($coverage -lt $MinimumCoverage) { throw "Copertura $coverage% sotto il minimo $MinimumCoverage%." }
}
finally {
    Pop-Location
}
