# Assistente-Aggiornamento — Catalogo ISO Windows 11 Hardened

Repository ad alta sicurezza per la catalogazione, validazione e verifica di integrità crittografica dei collegamenti alle immagini ISO di Windows 11.

---

## 🛡️ Architettura di Sicurezza

Il repository è strutturato secondo criteri di sicurezza *defense-in-depth* e zero-trust:

1. **Retrocompatibilità Invariata (`links.json`):** la mappa delle chiavi (`win11-23h2`, `win11-24h2`, `win11-25h2`, `win11-ltsc`) mantiene la struttura standard consumabile da script e toolchain esterne.
2. **Schema JSON Rigido (`schema/`):** validazione formale JSON Schema 2020-12 che vieta campi non autorizzati e vincola il formato di percorsi e URL.
3. **Manifest Crittografico Autoritativo (`catalog.manifest.json`):** contiene metadati completi, dimensioni esatte in byte, checksum SHA-1, MD5 e CRC32 estratti dai record d'archivio.
4. **File Checksum Standard (`checksums.sha1`, `checksums.md5`):** verificabili con strumenti UNIX/POSIX e PowerShell nativi.
5. **Toolchain PowerShell Indurita (`scripts/`):**
   - Compatibilità 100% garantita sia con **Windows PowerShell 5.1** che con **PowerShell Core (pwsh 7+)**.
   - `Set-StrictMode -Version Latest`, prevenzione path traversal (`..`, `%2e%2e`, backslash), allowlist rigida degli host (`archive.org`), porte consentite, rifiuto categorico di query string, frammenti e credenziali.
6. **Strumento di Verifica Utente (`Verify-IsoIntegrity.ps1`):** permette a chiunque scarichi un'immagine di validarne l'integrità prima di montarla o eseguirla.
7. **Suite di Test Automatizzata (`Validate-Links.Tests.ps1`):** verifica continua in CI/CD di casi positivi e negativi (rifiuto protocolli insicuri, domini non autorizzati, tentativi di injection, payload o file non conformi).
8. **Pipeline GitHub Actions Blindata:** permessi zero-trust (`permissions: {}`), checkout con credenziali disabilitate, commit SHA immutabili per tutte le actions, matrice multipiattaforma (`windows-latest`, `ubuntu-latest`).
9. **Firma Crittografica GPG:** ogni commit ufficiale è firmato digitalmente con chiave GPG verificabile.

---

## 📦 Catalogo Versioni Censite

| Chiave | Edizione | Dimensione | Checksum SHA-1 |
|---|---|---|---|
| `win11-23h2` | Windows 11 Consumer Editions 23H2 (Sep 2025) x64 Italian | 7.406.548.992 B | `77e93248f5ccaf8ae0fe3e44efefc916c3db258a` |
| `win11-24h2` | Windows 11 Consumer Editions 24H2 (Sep 2025) x64 Italian | 7.589.093.376 B | `93fbb724f607692352317b8f77587a2ad9c63274` |
| `win11-25h2` | Windows 11 25H2 Build 26200.6584 Client Consumer x64 FRE Italian | 7.644.715.008 B | `0f374ed0b34f7decb3203800b7c8de24efeaef8f` |
| `win11-ltsc` | Windows 11 Enterprise LTSC 2024 x64 Italian | 5.067.823.104 B | `1ab20dc8fbd98525ad6782e51eab3aa4f34c8e1d` |

> [!NOTE]
> Gli URL attuali puntano a copie archiviate su Archive.org. La disponibilità HTTP non attesta l'autenticità Microsoft del binario: prima di utilizzare l'immagine è obbligatorio verificarne l'hash. Per le immagini ufficiali dirette fare sempre riferimento al portale [Microsoft Software Download](https://www.microsoft.com/software-download/windows11).

---

## ⬇️ Download diretto (un clic)

| Chiave | Download | Dimensione |
|---|---|---|
| `win11-23h2` | [Scarica .iso](https://archive.org/download/it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d/it-it_windows_11_consumer_editions_version_23h2_updated_sep_2025_x64_dvd_98118d6e.iso) | 7.4 GB |
| `win11-24h2` | [Scarica .iso](https://archive.org/download/it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d/it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d.iso) | 7.6 GB |
| `win11-25h2` | [Scarica .iso](https://archive.org/download/it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_x64FRE_it-it.iso) | 7.6 GB |
| `win11-ltsc` | [Scarica .iso](https://archive.org/download/it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d/it-it_windows_11_enterprise_ltsc_2024_x64_dvd_1e8cabb6.iso) | 5.1 GB |

Il download parte da Archive.org. Dopo averlo scaricato, verifica l'immagine con `Verify-IsoIntegrity.ps1` (vedi sotto) prima di usarla.

---

## 🚀 Utilizzo e Validazione

### 1. Validazione del catalogo locale

Compatibile sia con PowerShell 7+ che con Windows PowerShell 5.1:

```powershell
# Esecuzione validatore
./scripts/Validate-Links.ps1

# Esecuzione della suite di test di sicurezza (11 test di regressione e sicurezza)

# Suite Pester con copertura (100% degli script)
./.github/scripts/Invoke-CoverageRun.ps1
./scripts/Validate-Links.Tests.ps1
```

### 2. Verifica di una ISO scaricata

Prima di montare o masterizzare un file ISO, verificarlo in streaming contro il manifest:

```powershell
# Rilevamento automatico della versione tramite nome file
.\scripts\Verify-IsoIntegrity.ps1 -IsoPath "C:\Download\it-it_windows_11_consumer_editions_version_24h2_updated_sep_2025_x64_dvd_6d1ad20d.iso"

# Oppure specificando la versione e controllando sia SHA-1 che MD5:
.\scripts\Verify-IsoIntegrity.ps1 -IsoPath "C:\Download\immagine.iso" -VersionKey "win11-24h2" -Algorithm ALL
```

---

## 🔐 Verifica Firma Commit (GPG)

I commit di questo repository sono firmati con la chiave GPG:
- **ID:** `CC21AE8B31EBE91F`
- **Fingerprint:** `99F1B31CFF6CC21485D87687CC21AE8B31EBE91F`
- **Autore:** Light Yagami (`maule2703@gmail.com`)

Per validare la firma dell'ultimo commit:
```bash
git log --show-signature -n 1
git verify-commit HEAD
```

---

## 📄 Licenza

Distribuito con licenza [MIT](LICENSE).
