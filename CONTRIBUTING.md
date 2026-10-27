# Contribuire

1. Apri una issue o una pull request da un ramo dedicato.
2. Prima di inviare, esegui in locale (PowerShell 7 o Windows PowerShell 5.1):
   ```powershell
   ./scripts/Validate-Links.ps1
   Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
   ./.github/scripts/Invoke-CoverageRun.ps1
   ```
   La copertura dei due script in `scripts/` deve restare al 100%: ogni nuova regola ha un test positivo e uno negativo in `tests/`.
3. Se cambi `links.json`, aggiorna insieme `catalog.manifest.json`, `checksums.sha1` e `checksums.md5`: il validatore controlla che coincidano.
4. Aggiungi una riga a `CHANGELOG.md`.
5. Le azioni di GitHub nei workflow vanno fissate a un commit SHA, con la versione in commento.

Vulnerabilità: non aprire issue pubbliche, usa le istruzioni di [SECURITY.md](SECURITY.md).
