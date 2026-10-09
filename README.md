# Assistente-Aggiornamento — catalogo ISO Windows

Questo repository contiene `links.json`, una mappa di identificatori di versione verso URL ISO. Manteniamo le chiavi esistenti perché possono essere consumate da altri strumenti.

## Fonte e verifica

Gli URL attuali puntano a snapshot di terze parti su Archive.org: non sono link Microsoft e la raggiungibilità HTTP non prova autenticità o integrità dell'immagine. Verificare l'hash ISO usando un riferimento Microsoft attendibile prima dell'installazione. Per l'ultima versione e i media ufficiali usare [Download Windows 11 di Microsoft](https://www.microsoft.com/software-download/windows11).

Secondo la [release information Microsoft](https://learn.microsoft.com/windows/release-health/windows11-release-information), Windows 11 26H2 è in General Availability dal 29 settembre 2026. Il catalogo non contiene ancora una ISO 26H2 verificata; non riutilizzare un link di un'altra versione e non aggiungere un mirror senza controllare build, lingua, architettura e hash.

## Validazione

Su PowerShell 7 o Windows PowerShell 5.1:

```powershell
./scripts/Validate-Links.ps1
```

La CI valida JSON, chiavi attese, HTTPS, host e percorso ISO. Non scarica le immagini, non ne verifica gli hash e non esegue installer. Dependabot controlla le GitHub Actions; CodeQL e SonarCloud non si applicano al solo catalogo JSON.
