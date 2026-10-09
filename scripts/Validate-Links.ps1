[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'links.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -AsHashtable
$expectedKeys = @('win11-23h2', 'win11-24h2', 'win11-25h2', 'win11-ltsc')
$actualKeys = @($catalog.Keys | Sort-Object)

if ((Compare-Object ($expectedKeys | Sort-Object) $actualKeys).Count -ne 0) {
    throw "Le chiavi del catalogo non corrispondono allo schema atteso: $($actualKeys -join ', ')"
}

foreach ($key in $expectedKeys) {
    $uri = $null
    if (-not [Uri]::TryCreate([string]$catalog[$key], [UriKind]::Absolute, [ref]$uri)) {
        throw "URL non assoluto o non valido per '$key'."
    }

    if ($uri.Scheme -ne [Uri]::UriSchemeHttps -or
        $uri.Host -ne 'archive.org' -or
        -not $uri.AbsolutePath.StartsWith('/download/', [StringComparison]::Ordinal) -or
        -not $uri.AbsolutePath.EndsWith('.iso', [StringComparison]::OrdinalIgnoreCase) -or
        $uri.Query -or $uri.Fragment -or $uri.UserInfo) {
        throw "URL non conforme alla policy (HTTPS Archive.org e percorso ISO diretto) per '$key'."
    }

    if ($uri.AbsoluteUri -match '(?i)test|placeholder|example\.com') {
        throw "Rilevato URL segnaposto per '$key'."
    }
}

Write-Output "Catalogo valido: $($expectedKeys.Count) URL HTTPS verso ISO Archive.org."
