#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Test Pester di Verify-IsoIntegrity.ps1 con un'immagine ISO finta e un manifest su misura.
#>

BeforeAll {
    $script:Verifier = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts/Verify-IsoIntegrity.ps1'))

    function Save-Json($Path, $Object) {
        [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    }

    function New-IsoFixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        $iso = Join-Path $root 'finta.iso'
        [System.IO.File]::WriteAllBytes($iso, [byte[]](1..200))
        $manifest = @{
            images = @{
                'win11-24h2' = @{
                    filename  = 'finta.iso'
                    edition   = 'Edizione di prova'
                    sizeBytes = 200
                    sha1      = (Get-FileHash -LiteralPath $iso -Algorithm SHA1).Hash.ToLowerInvariant()
                    md5       = (Get-FileHash -LiteralPath $iso -Algorithm MD5).Hash.ToLowerInvariant()
                }
            }
        }
        Save-Json (Join-Path $root 'catalog.manifest.json') $manifest
        [pscustomobject]@{ Root = $root; Iso = $iso }
    }

    function Set-Image($Fx, [string]$Name, $Value) {
        $path = Join-Path $Fx.Root 'catalog.manifest.json'
        $obj = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $obj.images.'win11-24h2'.$Name = $Value
        Save-Json $path $obj
    }
}

Describe 'Verify-IsoIntegrity.ps1' {
    BeforeEach { $script:fx = New-IsoFixture }
    AfterEach  { Remove-Item -LiteralPath $script:fx.Root -Recurse -Force -ErrorAction SilentlyContinue }

    Context 'immagine integra' {
        It 'verifica SHA-1 (predefinito) con rilevamento automatico della versione' {
            $out = & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root
            $LASTEXITCODE | Should -Be 0
            ($out -join "`n") | Should -Match 'INTEGRO E CONFORME'
            ($out -join "`n") | Should -Match 'win11-24h2'
        }

        It 'verifica solo MD5' {
            $out = & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root -Algorithm MD5
            ($out -join "`n") | Should -Match 'MD5 calcolato'
            ($out -join "`n") | Should -Not -Match 'SHA-1 calcolato'
        }

        It 'verifica SHA-1 e MD5 insieme con la chiave indicata' {
            $out = & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root -VersionKey win11-24h2 -Algorithm ALL
            ($out -join "`n") | Should -Match 'SHA-1 calcolato'
            ($out -join "`n") | Should -Match 'MD5 calcolato'
            ($out -join "`n") | Should -Match 'INTEGRO E CONFORME'
        }

        It 'usa il manifest del repository quando RepoRoot non e indicato' {
            { & $script:Verifier -IsoPath $script:fx.Iso } | Should -Throw '*Nessuna corrispondenza*'
        }
    }

    Context 'immagine non conforme' {
        It 'rifiuta un hash SHA-1 diverso' {
            Set-Image $script:fx 'sha1' ('0' * 40)
            { & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root } | Should -Throw '*NON CONFORME*'
        }

        It 'rifiuta un hash MD5 diverso' {
            Set-Image $script:fx 'md5' ('0' * 32)
            { & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root -Algorithm MD5 } | Should -Throw '*NON CONFORME*'
        }

        It 'avvisa e rifiuta una dimensione diversa' {
            Set-Image $script:fx 'sizeBytes' 999
            { & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root -WarningAction SilentlyContinue } | Should -Throw '*NON CONFORME*'
        }
    }

    Context 'errori di input' {
        It 'rifiuta un file ISO inesistente' {
            { & $script:Verifier -IsoPath (Join-Path $script:fx.Root 'manca.iso') -RepoRoot $script:fx.Root } | Should -Throw '*File ISO non trovato*'
        }

        It 'rifiuta una cartella senza manifest' {
            Remove-Item (Join-Path $script:fx.Root 'catalog.manifest.json')
            { & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root } | Should -Throw '*catalog.manifest.json non trovato*'
        }

        It 'rifiuta una chiave assente dal manifest' {
            { & $script:Verifier -IsoPath $script:fx.Iso -RepoRoot $script:fx.Root -VersionKey win11-ltsc } | Should -Throw "*'win11-ltsc' non trovata*"
        }

        It 'rifiuta un file che il manifest non conosce' {
            $altro = Join-Path $script:fx.Root 'sconosciuta.iso'
            [System.IO.File]::WriteAllBytes($altro, [byte[]](1..10))
            { & $script:Verifier -IsoPath $altro -RepoRoot $script:fx.Root } | Should -Throw '*Nessuna corrispondenza*'
        }
    }
}
