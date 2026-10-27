# Changelog

Formato basato su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/); versioni del catalogo secondo `catalog.manifest.json`.

## [Non rilasciato]

### Aggiunto
- Suite Pester (`tests/`) con copertura del 100% di `Validate-Links.ps1` e `Verify-IsoIntegrity.ps1`, eseguita su Linux, Windows, macOS e Windows PowerShell 5.1.
- Invio della copertura a SonarCloud tramite `.github/scripts/Convert-CoverageToSonar.ps1`.
- Controllo dei checksum anche su `checksums.md5`, con confronto del valore dell'hash con il manifest (prima si verificava solo il nome del file in `checksums.sha1`).
- Controlli sul manifest: campo `key` coerente, `filename` uguale al nome file dell'URL, `crc32` di 8 cifre esadecimali.
- Parametro `-RepoRoot` negli script, per eseguirli su una copia di lavoro.
- File di progetto: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS`, `.editorconfig`, modelli di issue e di pull request.

### Corretto
- Con `Set-StrictMode -Version Latest` i messaggi "images mancante", "chiave mancante nel manifest" e "chiave non trovata" non venivano mai raggiunti: la lettura di una proprietà assente lanciava un errore generico.
- Rimossi due `exit 1` irraggiungibili dopo `Write-Error` (con `ErrorActionPreference = Stop` termina già lo script) e un ramo di errore irraggiungibile in `Compute-StreamHash`.

## [1.1.0] - 2026-10-20

### Aggiunto
- Manifest crittografico `catalog.manifest.json`, file `checksums.sha1` e `checksums.md5`, schemi JSON, script di validazione e verifica ISO, pipeline GitHub Actions su più sistemi operativi.
