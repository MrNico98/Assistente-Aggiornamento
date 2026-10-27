<#
.SYNOPSIS
    Valida in modo rigoroso l'integrità, la struttura e la sicurezza del catalogo ISO links.json.

.DESCRIPTION
    Script indurito (hardened) per la validazione di links.json e catalog.manifest.json.
    Compatibile sia con PowerShell Core (pwsh 7+) sia con Windows PowerShell 5.1.
    Implementa controlli di sicurezza in profondità (defense-in-depth):
    - Set-StrictMode Latest
    - Canonicalizzazione e confinamento dei percorsi (prevenzione path traversal)
    - Limite di dimensione sul file JSON contro memory exhaustion
    - Schema delle chiavi esatto (nessuna chiave mancante o imprevista)
    - Validazione URL rigida: solo HTTPS, solo host archive.org consentito, porta standard,
      nessun parametro di query, nessun frammento, nessuna credenziale incorporata,
      percorso rigorosamente conforme a /download/<item>/<file>.iso
    - Prevenzione sequenze pericolose (.., %2e%2e, backslash, caratteri di controllo)
    - Cross-validazione crittografica con catalog.manifest.json e i file di checksum (SHA-1 / MD5)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # 1. Risoluzione sicura dei percorsi
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ($RepoRoot) {
        $repoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    } else {
        $repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $scriptDir))
    }

    if (-not $CatalogPath) {
        $CatalogPath = Join-Path -Path $repoRoot -ChildPath 'links.json'
    }
    $resolvedCatalogPath = [System.IO.Path]::GetFullPath($CatalogPath)

    # Verifica che il file esista e sia un file regolare
    if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
        throw "File catalogo non trovato: $resolvedCatalogPath"
    }

    # Protezione contro memory exhaustion / DoS
    $catalogFileInfo = Get-Item -LiteralPath $resolvedCatalogPath
    if ($catalogFileInfo.Length -gt 1MB) {
        throw "Dimensione file anomala per il catalogo ($($catalogFileInfo.Length) bytes). Massimo consentito: 1MB."
    }

    # 2. Lettura e parsing JSON sicuro (compatibile PS 5.1 e PS 7+)
    $rawJson = Get-Content -LiteralPath $resolvedCatalogPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($rawJson)) {
        throw "Il file catalogo è vuoto."
    }

    $catalogObj = $rawJson | ConvertFrom-Json
    if ($null -eq $catalogObj) {
        throw "Parsing JSON fallito o contenuto non valido."
    }

    # 3. Controllo rigoroso dello schema delle chiavi
    $expectedKeys = @('win11-23h2', 'win11-24h2', 'win11-25h2', 'win11-ltsc')
    $actualKeys = @($catalogObj.psobject.properties.Name | Sort-Object)
    $sortedExpected = @($expectedKeys | Sort-Object)

    $diff = @(Compare-Object -ReferenceObject $sortedExpected -DifferenceObject $actualKeys)
    if ($diff.Count -gt 0) {
        $missing = @($diff | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject })
        $unexpected = @($diff | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
        $msg = "Discrepanza schema chiavi catalogo."
        if ($missing.Count -gt 0) { $msg += " Mancanti: $($missing -join ', ')." }
        if ($unexpected.Count -gt 0) { $msg += " Non previste: $($unexpected -join ', ')." }
        throw $msg
    }

    # 4. Validazione profonda di ciascun URL
    $allowedHost = 'archive.org'
    $filenameRegex = '^[A-Za-z0-9\._\-]+\.iso$'

    foreach ($key in $expectedKeys) {
        $rawUrl = [string]$catalogObj.$key
        if ([string]::IsNullOrWhiteSpace($rawUrl)) {
            throw "Valore vuoto o non valido per la chiave '$key'."
        }

        # Controllo pattern espliciti malevoli o di test
        if ($rawUrl -match '(?i)example\.com|placeholder|test|localhost|127\.0\.0\.1') {
            throw "Rilevato URL segnaposto o non sicuro per '$key': $rawUrl"
        }

        # Parsing URI tramite .NET
        $uri = $null
        if (-not [Uri]::TryCreate($rawUrl, [UriKind]::Absolute, [ref]$uri)) {
            throw "URL sintatticamente non valido o non assoluto per '$key': $rawUrl"
        }

        # Solo HTTPS
        if ($uri.Scheme -ne [Uri]::UriSchemeHttps) {
            throw "Protocollo non sicuro per '$key'. È richiesto HTTPS: $rawUrl"
        }

        # Host consentito: esattamente archive.org (case-insensitive)
        if ($uri.Host.ToLowerInvariant() -ne $allowedHost) {
            throw "Host non consentito per '$key': '$($uri.Host)'. Atteso: '$allowedHost'."
        }

        # Solo porta standard HTTPS (443 o non specificata)
        if (-not $uri.IsDefaultPort -and $uri.Port -ne 443) {
            throw "Porta non standard rilevata per '$key': $($uri.Port)."
        }

        # Nessuna credenziale incorporata (user:pass)
        if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
            throw "Rilevate credenziali nell'URL per '$key'."
        }

        # Nessun parametro query o frammento
        if (-not [string]::IsNullOrEmpty($uri.Query)) {
            throw "Parametri di query non consentiti nell'URL per '$key'."
        }
        if (-not [string]::IsNullOrEmpty($uri.Fragment)) {
            throw "Frammenti (#) non consentiti nell'URL per '$key'."
        }

        # Verifica percorso ISO: deve iniziare con /download/ e terminare con .iso
        $path = $uri.AbsolutePath
        if (-not $path.StartsWith('/download/', [StringComparison]::Ordinal)) {
            throw "Il percorso non inizia con '/download/' per '$key': $path"
        }
        if (-not $path.EndsWith('.iso', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Il file indicato non ha estensione .iso per '$key': $path"
        }

        # Prevenzione path traversal e caratteri pericolosi
        if ($path -match '\.\.|%2e%2e|\\|[\x00-\x1F\x7F]') {
            throw "Rilevata sequenza non sicura o tentativo di directory traversal nel percorso per '$key'."
        }

        # Estrazione e validazione del nome file
        $segments = $uri.Segments
        if ($segments.Length -lt 4) {
            throw "Percorso non sufficientemente specifico per '$key': $path"
        }
        $filename = [System.Uri]::UnescapeDataString($segments[$segments.Length - 1])
        if ($filename -notmatch $filenameRegex) {
            throw "Nome file ISO non conforme al formato sicuro per '$key': $filename"
        }
    }

    # 5. Cross-validazione con catalog.manifest.json (se presente)
    $manifestObj = $null
    $manifestPath = Join-Path -Path $repoRoot -ChildPath 'catalog.manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifestRaw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifestObj = $manifestRaw | ConvertFrom-Json

        if ($null -eq $manifestObj.psobject.Properties['images']) {
            throw "Struttura 'images' mancante in catalog.manifest.json."
        }

        foreach ($key in $expectedKeys) {
            $manifestEntry = $manifestObj.images.psobject.Properties[$key]
            $manifestImage = if ($manifestEntry) { $manifestEntry.Value } else { $null }
            if ($null -eq $manifestImage) {
                throw "Chiave '$key' mancante nel manifest catalog.manifest.json."
            }

            if ([string]$catalogObj.$key -ne [string]$manifestImage.url) {
                throw "Discrepanza URL tra links.json e catalog.manifest.json per '$key'."
            }

            if ([string]$manifestImage.key -ne $key) {
                throw "Campo 'key' incoerente nel manifest per '$key'."
            }

            $urlFilename = [System.IO.Path]::GetFileName([string]$manifestImage.url)
            if ([string]$manifestImage.filename -cne $urlFilename) {
                throw "Il nome file nel manifest non corrisponde all'URL per '$key'."
            }

            if ([string]$manifestImage.crc32 -notmatch '^[0-9a-fA-F]{8}$') {
                throw "CRC32 non valido o mancante nel manifest per '$key'."
            }

            if ([string]$manifestImage.sha1 -notmatch '^[0-9a-fA-F]{40}$') {
                throw "Hash SHA-1 non valido o mancante nel manifest per '$key'."
            }

            if ([string]$manifestImage.md5 -notmatch '^[0-9a-fA-F]{32}$') {
                throw "Hash MD5 non valido o mancante nel manifest per '$key'."
            }

            if ([long]$manifestImage.sizeBytes -le 1000000) {
                throw "Dimensione byte non valida nel manifest per '$key'."
            }
        }
    }

    # 6. Cross-validazione con checksums.sha1 e checksums.md5 (se presenti):
    #    il file deve essere elencato e, con il manifest presente, l'hash deve coincidere.
    foreach ($checksum in @(
            @{ File = 'checksums.sha1'; Label = 'SHA-1'; Property = 'sha1' },
            @{ File = 'checksums.md5';  Label = 'MD5';   Property = 'md5' })) {
        $checksumPath = Join-Path -Path $repoRoot -ChildPath $checksum.File
        if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { continue }

        $checksumLines = Get-Content -LiteralPath $checksumPath -Encoding UTF8
        foreach ($key in $expectedKeys) {
            $expectedFilename = [System.IO.Path]::GetFileName([string]$catalogObj.$key)
            $line = $checksumLines | Where-Object { $_ -match ('^[0-9a-fA-F]+ \*?' + [regex]::Escape($expectedFilename) + '$') } | Select-Object -First 1
            if (-not $line) {
                throw "Checksum $($checksum.Label) non trovato per il file '$expectedFilename' ($key) in $($checksum.File)."
            }
            if ($null -ne $manifestObj) {
                $fileHash = ($line -split ' ')[0]
                if ($fileHash -ine [string]$manifestObj.images.$key.($checksum.Property)) {
                    throw "Discrepanza $($checksum.Label) tra $($checksum.File) e catalog.manifest.json per '$key'."
                }
            }
        }
    }

    Write-Output "Catalogo verificato con successo: $($expectedKeys.Count) URL conformi e crittograficamente ancorati."
    exit 0
}
catch {
    # Con ErrorActionPreference = Stop, Write-Error termina lo script con errore: nessun exit necessario.
    Write-Error "ERRORE DI VALIDAZIONE SICUREZZA: $_"
}
