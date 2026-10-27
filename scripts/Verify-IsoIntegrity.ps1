<#
.SYNOPSIS
    Verifica crittograficamente l'integrità e l'autenticità di un file ISO scaricato rispetto al manifest.

.DESCRIPTION
    Calcola l'hash crittografico (SHA-1 / MD5) e controlla la dimensione esatta in byte
    rispetto ai valori registrati in catalog.manifest.json.
    Supporta lo streaming del file per evitare saturazione di memoria su immagini da 7+ GB.

.PARAMETER IsoPath
    Percorso locale del file ISO da verificare.

.PARAMETER VersionKey
    Chiave facoltativa del catalogo (win11-23h2, win11-24h2, win11-25h2, win11-ltsc).
    Se omessa, lo script rileva automaticamente la versione corrispondente tramite nome file.

.PARAMETER Algorithm
    Algoritmo di verifica (SHA1, MD5, o ALL). Default: SHA1.

.EXAMPLE
    .\scripts\Verify-IsoIntegrity.ps1 -IsoPath "C:\ISO\it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$IsoPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('win11-23h2', 'win11-24h2', 'win11-25h2', 'win11-ltsc')]
    [string]$VersionKey,

    [Parameter(Mandatory = $false)]
    [ValidateSet('SHA1', 'MD5', 'ALL')]
    [string]$Algorithm = 'SHA1',

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Compute-StreamHash {
    param(
        [string]$FilePath,
        [string]$AlgoName
    )
    $hasher = $null
    $stream = $null
    try {
        # AlgoName e sempre SHA1 o MD5: il parametro dello script e vincolato da ValidateSet.
        if ($AlgoName -eq 'SHA1') {
            $hasher = [System.Security.Cryptography.SHA1]::Create()
        } else {
            $hasher = [System.Security.Cryptography.MD5]::Create()
        }

        $stream = [System.IO.File]::OpenRead($FilePath)
        $hashBytes = $hasher.ComputeHash($stream)
        $sb = [System.Text.StringBuilder]::new($hashBytes.Length * 2)
        foreach ($b in $hashBytes) {
            [void]$sb.Append($b.ToString("x2"))
        }
        return $sb.ToString()
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $hasher) { $hasher.Dispose() }
    }
}

try {
    # Risoluzione percorso file
    $resolvedIsoPath = [System.IO.Path]::GetFullPath($IsoPath)
    if (-not (Test-Path -LiteralPath $resolvedIsoPath -PathType Leaf)) {
        throw "File ISO non trovato: $resolvedIsoPath"
    }

    $fileInfo = Get-Item -LiteralPath $resolvedIsoPath
    $actualFileName = $fileInfo.Name
    $actualSizeBytes = $fileInfo.Length

    # Caricamento manifest
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ($RepoRoot) {
        $repoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    } else {
        $repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $scriptDir))
    }
    $manifestPath = Join-Path -Path $repoRoot -ChildPath 'catalog.manifest.json'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "catalog.manifest.json non trovato in $repoRoot"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # Determinazione record atteso
    $targetEntry = $null
    $matchedKey = $null

    if ($VersionKey) {
        $matchedKey = $VersionKey
        $imageEntry = $manifest.images.psobject.Properties[$VersionKey]
        $targetEntry = if ($imageEntry) { $imageEntry.Value } else { $null }
        if ($null -eq $targetEntry) {
            throw "Chiave '$VersionKey' non trovata in catalog.manifest.json."
        }
    } else {
        foreach ($prop in $manifest.images.psobject.properties) {
            if ($prop.Value.filename -ieq $actualFileName) {
                $matchedKey = $prop.Name
                $targetEntry = $prop.Value
                break
            }
        }
        if ($null -eq $targetEntry) {
            throw "Nessuna corrispondenza trovata nel manifest per il file '$actualFileName'. Specificare -VersionKey."
        }
    }

    Write-Output "============================================================"
    Write-Output "VERIFICA INTEGRITÀ ISO — ASSISTENTE AGGIORNAMENTO"
    Write-Output "============================================================"
    Write-Output "File analizzato:  $resolvedIsoPath"
    Write-Output "Versione rilevata: $matchedKey ($($targetEntry.edition))"
    Write-Output "Nome atteso:      $($targetEntry.filename)"
    Write-Output "Dimensione reale: $actualSizeBytes bytes"
    Write-Output "Dimensione attesa: $($targetEntry.sizeBytes) bytes"

    $sizeMatch = ($actualSizeBytes -eq [long]$targetEntry.sizeBytes)
    if (-not $sizeMatch) {
        Write-Warning "ATTENZIONE: La dimensione del file NON corrisponde al manifest!"
    }

    $sha1Match = $true
    $md5Match = $true

    if ($Algorithm -eq 'SHA1' -or $Algorithm -eq 'ALL') {
        Write-Output "Calcolo hash SHA-1 in corso (streaming)..."
        $computedSha1 = Compute-StreamHash -FilePath $resolvedIsoPath -AlgoName 'SHA1'
        Write-Output "SHA-1 calcolato: $computedSha1"
        Write-Output "SHA-1 atteso:    $($targetEntry.sha1)"
        $sha1Match = ($computedSha1 -ieq [string]$targetEntry.sha1)
    }

    if ($Algorithm -eq 'MD5' -or $Algorithm -eq 'ALL') {
        Write-Output "Calcolo hash MD5 in corso (streaming)..."
        $computedMd5 = Compute-StreamHash -FilePath $resolvedIsoPath -AlgoName 'MD5'
        Write-Output "MD5 calcolato:   $computedMd5"
        Write-Output "MD5 atteso:      $($targetEntry.md5)"
        $md5Match = ($computedMd5 -ieq [string]$targetEntry.md5)
    }

    Write-Output "------------------------------------------------------------"
    if ($sizeMatch -and $sha1Match -and $md5Match) {
        Write-Output "ESITO VERIFICA: [INTEGRO E CONFORME AL MANIFEST]"
        Write-Output "Nota: L'immagine corrisponde al record d'archivio censito."
        exit 0
    } else {
        Write-Error "ESITO VERIFICA: [NON CONFORME / MANOMESSO O CORROTTO]"
    }
}
catch {
    # Con ErrorActionPreference = Stop, Write-Error termina lo script con errore: nessun exit necessario.
    Write-Error "ERRORE DURANTE LA VERIFICA: $_"
}
