<#
.SYNOPSIS
    Usa Pester 5 se già installato, altrimenti lo scarica alla versione fissata riprovando se la PowerShell Gallery non risponde.
#>
[CmdletBinding()]
param(
    [string]$Version = '5.7.1',
    [int]$Attempts = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# I runner di GitHub hanno già Pester 5: si scarica dalla Gallery solo se manca.
$presente = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Select-Object -First 1
if ($presente) {
    Write-Output "Pester $($presente.Version) già installato."
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
for ($i = 1; $i -le $Attempts; $i++) {
    try {
        Install-Module Pester -RequiredVersion $Version -Scope CurrentUser -Force -SkipPublisherCheck
        return
    }
    catch {
        if ($i -eq $Attempts) { throw }
        Write-Warning "Installazione di Pester non riuscita (tentativo $i di $Attempts): $($_.Exception.Message)"
        Start-Sleep -Seconds (5 * $i)
    }
}
