#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Test Pester di Validate-Links.ps1: ogni regola di sicurezza ha un caso positivo e uno negativo.
#>

BeforeAll {
    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:Validator = Join-Path $script:RepoRoot 'scripts/Validate-Links.ps1'

    # Crea una copia di lavoro di catalogo, manifest e checksum, modificabile dal singolo test.
    function New-Fixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($f in 'links.json', 'catalog.manifest.json', 'checksums.sha1', 'checksums.md5') {
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot $f) -Destination $root
        }
        $root
    }

    function Save-Json($Path, $Object) {
        [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    }

    function Set-Catalog($Root, $Mutate) {
        $path = Join-Path $Root 'links.json'
        $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        & $Mutate $obj
        Save-Json $path $obj
    }

    function Set-Manifest($Root, $Mutate) {
        $path = Join-Path $Root 'catalog.manifest.json'
        $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        & $Mutate $obj
        Save-Json $path $obj
    }

    function Invoke-Validator($Root, [string]$CatalogPath) {
        if ($CatalogPath) {
            & $script:Validator -RepoRoot $Root -CatalogPath $CatalogPath
        } else {
            & $script:Validator -RepoRoot $Root
        }
    }
}

Describe 'Validate-Links.ps1' {
    BeforeEach { $script:fx = New-Fixture }
    AfterEach  { Remove-Item -LiteralPath $script:fx -Recurse -Force -ErrorAction SilentlyContinue }

    Context 'catalogo valido' {
        It 'accetta il catalogo ufficiale' {
            $out = Invoke-Validator $script:fx
            $LASTEXITCODE | Should -Be 0
            ($out -join "`n") | Should -Match '4 URL conformi'
        }

        It 'usa i percorsi del repository quando RepoRoot non e indicato' {
            $out = & $script:Validator
            $LASTEXITCODE | Should -Be 0
            ($out -join "`n") | Should -Match 'verificato con successo'
        }

        It 'accetta il catalogo anche senza manifest e checksum' {
            Remove-Item (Join-Path $script:fx 'catalog.manifest.json'), (Join-Path $script:fx 'checksums.sha1'), (Join-Path $script:fx 'checksums.md5')
            Invoke-Validator $script:fx | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'controlla solo il nome file dei checksum quando manca il manifest' {
            Remove-Item (Join-Path $script:fx 'catalog.manifest.json')
            Invoke-Validator $script:fx | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'accetta un percorso catalogo esplicito' {
            Invoke-Validator $script:fx (Join-Path $script:fx 'links.json') | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context 'file del catalogo' {
        It 'rifiuta un file inesistente' {
            { Invoke-Validator $script:fx (Join-Path $script:fx 'manca.json') } | Should -Throw '*File catalogo non trovato*'
        }

        It 'rifiuta un file piu grande di 1 MB' {
            $big = Join-Path $script:fx 'big.json'
            [System.IO.File]::WriteAllText($big, ('x' * (1MB + 10)))
            { Invoke-Validator $script:fx $big } | Should -Throw '*Dimensione file anomala*'
        }

        It 'rifiuta un file vuoto' {
            $empty = Join-Path $script:fx 'empty.json'
            [System.IO.File]::WriteAllText($empty, '   ')
            { Invoke-Validator $script:fx $empty } | Should -Throw '*vuoto*'
        }

        It 'rifiuta un JSON null' {
            $nul = Join-Path $script:fx 'null.json'
            [System.IO.File]::WriteAllText($nul, 'null')
            { Invoke-Validator $script:fx $nul } | Should -Throw '*Parsing JSON fallito*'
        }

        It 'rifiuta un JSON corrotto' {
            $bad = Join-Path $script:fx 'bad.json'
            [System.IO.File]::WriteAllText($bad, "{ 'broken': json")
            { Invoke-Validator $script:fx $bad } | Should -Throw '*ERRORE DI VALIDAZIONE*'
        }
    }

    Context 'schema delle chiavi' {
        It 'segnala la chiave mancante' {
            Set-Catalog $script:fx { param($o) $o.psobject.Properties.Remove('win11-ltsc') }
            { Invoke-Validator $script:fx } | Should -Throw '*Mancanti: win11-ltsc*'
        }

        It 'segnala la chiave imprevista' {
            Set-Catalog $script:fx { param($o) $o | Add-Member -NotePropertyName 'win11-backdoor' -NotePropertyValue 'https://archive.org/download/a/b.iso' }
            { Invoke-Validator $script:fx } | Should -Throw '*Non previste: win11-backdoor*'
        }
    }

    Context 'validazione degli URL' {
        It 'rifiuta <Nome>' -ForEach @(
            @{ Nome = 'un valore vuoto';                 Url = '';                                                         Atteso = '*Valore vuoto*' }
            @{ Nome = 'un segnaposto';                   Url = 'https://archive.org/download/placeholder/a.iso';           Atteso = '*segnaposto*' }
            @{ Nome = 'un URL non assoluto';             Url = 'non-un-url';                                               Atteso = '*non valido o non assoluto*' }
            @{ Nome = 'HTTP non cifrato';                Url = 'http://archive.org/download/item/image.iso';               Atteso = '*Protocollo non sicuro*' }
            @{ Nome = 'un host diverso';                 Url = 'https://archive.org.attacker.net/download/item/image.iso'; Atteso = '*Host non consentito*' }
            @{ Nome = 'una porta non standard';          Url = 'https://archive.org:8443/download/item/image.iso';         Atteso = '*Porta non standard*' }
            @{ Nome = 'credenziali incorporate';         Url = 'https://user:pw@archive.org/download/item/image.iso';      Atteso = '*credenziali*' }
            @{ Nome = 'parametri di query';              Url = 'https://archive.org/download/item/image.iso?x=1';          Atteso = '*query non consentiti*' }
            @{ Nome = 'un frammento';                    Url = 'https://archive.org/download/item/image.iso#frag';         Atteso = '*Frammenti*' }
            @{ Nome = 'un percorso fuori da /download/'; Url = 'https://archive.org/details/item/image.iso';                Atteso = '*non inizia con*' }
            @{ Nome = 'un file senza estensione .iso';   Url = 'https://archive.org/download/item/payload.exe';            Atteso = '*estensione .iso*' }
            @{ Nome = 'una sequenza di path traversal';  Url = 'https://archive.org/download/item/a..b.iso';               Atteso = '*directory traversal*' }
            @{ Nome = 'un percorso troppo corto';        Url = 'https://archive.org/download/image.iso';                   Atteso = '*non sufficientemente specifico*' }
            @{ Nome = 'un nome file non conforme';       Url = 'https://archive.org/download/item/a%20b.iso';              Atteso = '*non conforme al formato sicuro*' }
        ) {
            Set-Catalog $script:fx { param($o) $o.'win11-23h2' = $Url }
            { Invoke-Validator $script:fx } | Should -Throw $Atteso
        }
    }

    Context 'manifest' {
        It 'rifiuta un manifest senza images' {
            Set-Manifest $script:fx { param($o) $o.psobject.Properties.Remove('images') }
            { Invoke-Validator $script:fx } | Should -Throw "*'images' mancante*"
        }

        It 'rifiuta un manifest senza una chiave del catalogo' {
            Set-Manifest $script:fx { param($o) $o.images.psobject.Properties.Remove('win11-ltsc') }
            { Invoke-Validator $script:fx } | Should -Throw "*'win11-ltsc' mancante nel manifest*"
        }

        It 'rifiuta un URL diverso tra catalogo e manifest' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-24h2'.url = 'https://archive.org/download/item/altro.iso' }
            { Invoke-Validator $script:fx } | Should -Throw '*Discrepanza URL*'
        }

        It 'rifiuta un campo key incoerente' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.key = 'win11-24h2' }
            { Invoke-Validator $script:fx } | Should -Throw "*Campo 'key' incoerente*"
        }

        It 'rifiuta un nome file diverso da quello dell URL' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.filename = 'altro.iso' }
            { Invoke-Validator $script:fx } | Should -Throw '*nome file nel manifest non corrisponde*'
        }

        It 'rifiuta un CRC32 non valido' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.crc32 = 'zz' }
            { Invoke-Validator $script:fx } | Should -Throw '*CRC32 non valido*'
        }

        It 'rifiuta un SHA-1 non valido' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.sha1 = 'abc' }
            { Invoke-Validator $script:fx } | Should -Throw '*SHA-1 non valido*'
        }

        It 'rifiuta un MD5 non valido' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.md5 = 'abc' }
            { Invoke-Validator $script:fx } | Should -Throw '*MD5 non valido*'
        }

        It 'rifiuta una dimensione troppo piccola' {
            Set-Manifest $script:fx { param($o) $o.images.'win11-23h2'.sizeBytes = 10 }
            { Invoke-Validator $script:fx } | Should -Throw '*Dimensione byte non valida*'
        }
    }

    Context 'checksum' {
        It 'rifiuta un checksums.sha1 senza il file del catalogo' {
            Set-Content -LiteralPath (Join-Path $script:fx 'checksums.sha1') -Value 'deadbeef  altro.iso'
            { Invoke-Validator $script:fx } | Should -Throw '*Checksum SHA-1 non trovato*'
        }

        It 'rifiuta un checksums.md5 senza il file del catalogo' {
            Set-Content -LiteralPath (Join-Path $script:fx 'checksums.md5') -Value 'deadbeef  altro.iso'
            { Invoke-Validator $script:fx } | Should -Throw '*Checksum MD5 non trovato*'
        }

        It 'rifiuta un hash SHA-1 diverso dal manifest' {
            $path = Join-Path $script:fx 'checksums.sha1'
            $righe = Get-Content -LiteralPath $path
            $righe[0] = ('0' * 40) + ' ' + ($righe[0] -split ' ', 2)[1]
            Set-Content -LiteralPath $path -Value $righe
            { Invoke-Validator $script:fx } | Should -Throw '*Discrepanza SHA-1*'
        }

        It 'rifiuta un hash MD5 diverso dal manifest' {
            $path = Join-Path $script:fx 'checksums.md5'
            $righe = Get-Content -LiteralPath $path
            $righe[1] = ('0' * 32) + ' ' + ($righe[1] -split ' ', 2)[1]
            Set-Content -LiteralPath $path -Value $righe
            { Invoke-Validator $script:fx } | Should -Throw '*Discrepanza MD5*'
        }
    }
}
