# HealthyIG: Android Build & Installation Guide (WSL/Linux)

This documentation describes the technical steps required to build, patch, and install HealthyIG in a Linux or WSL (Windows Subsystem for Linux) environment.

---

## 1. System Requirements

Ensure that the following packages are installed in your Linux environment:

```bash
sudo apt update
sudo apt install apktool zipalign apksigner default-jdk git python3-pip -y

```

To enable the progress bar display during script execution, install the `tqdm` Python module:

```bash
pip3 install tqdm

```

---

## 2. Original APK Acquisition

Download the source Instagram APK from a verified source (e.g., APKMirror) respecting the following technical constraints:

- **Architecture:** `arm64-v8a` (standard for modern Android devices).
- **DPI:** `nodpi` (necessary to ensure correct resource decompilation).
- **Format:** `APK` (Bundle or APKM formats are not supported by `apktool`).

Rename the downloaded file to `ig.apk` and place it in the project's root directory.

---

Note for WSL users: Your Windows files are usually located in `/mnt/c/Users/YourUserName/Downloads/`.

---

## 3. Environment Configuration and Script Fix

To avoid execution errors due to compatibility between Windows and Linux file systems, the patch script must be sanitized:

```bash
# Conversion of line endings from CRLF to LF
sed -i 's/\r$//' script.sh

# Correction of the xargs interpreter for handling special characters (apostrophes)
sed -i 's/xargs/xargs -d "\\n"/g' script.sh

# Assigning execution permissions
chmod +x script.sh

```

---

## 4. Build Procedure

Execute the commands in the order shown to generate the modified package:

1. **Decompilation:**
   `apktool d -r -f -o ig_plain ig.apk`
2. **Patch Application:**
   `./script.sh`
3. **Compilation:**
   `apktool b -r -f ig_plain`
4. **Resource Alignment:**
   `zipalign -v 4 ig_plain/dist/ig.apk install.apk`

---

## 5. Key Generation and Digital Signature

Android requires the package to be digitally signed. The following commands generate a key and apply the signature to ensure compatibility with current devices.

### Keystore Generation:

```bash
keytool -genkeypair -v -keystore healthyig.jks -alias key0 -keyalg RSA -keysize 2048 -validity 10000 -storepass password -keypass password -dname "CN=HealthyIG, O=Android, C=IT"

```

### Applying the Signature:

```bash
apksigner sign --ks ./healthyig.jks --ks-pass pass:password --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --min-sdk-version 21 install.apk

```

## 6. Installation

Previously remove the official Instagram application from the device (including any "Dual App" or "Private Space" profiles). To install the new `install.apk` package, proceed with one of the following methods:

### Option A: Manual transfer and installation (Recommended)

This procedure is suitable if you do not have an ADB environment configured on Windows.

1. **Transfer:** Send the `install.apk` file to the mobile device using file transfer tools (e.g., **LocalSend**, Telegram, or MTP cable connection).
2. **Permissions:** Locate the file via a File Manager on the device and launch it. If prompted, authorize the system to install from "Unknown sources" for the application used.
3. **Play Protect:** If Google Play Protect flags the app as unverified, select "More details" and proceed with "Install anyway".

### Option B: Via ADB (Android Debug Bridge)

Recommended for direct installation from the terminal and for monitoring any system errors.

1. Enable **Developer Options** and **USB Debugging** on the device.
2. Connect the device to the PC and verify the connection via `adb devices`.
3. Execute the installation command:

```powershell
adb install -r install.apk

```

---

## 7. Troubleshooting

| Error                             | Cause                                               | Solution                                                       |
| --------------------------------- | --------------------------------------------------- | -------------------------------------------------------------- |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | APK architecture incompatible with the CPU.         | Download the `arm64-v8a` variant.                              |
| `App not installed`               | Signature conflict or residues of the original app. | Uninstall Instagram for all users and verify the V1 signature. |
| `/bin/bash^M: bad interpreter`    | Windows file format (CRLF).                         | Execute the `sed` command described in point 3.                |

---

---

# HealthyIG: Android Build & Installation Guide (WSL/Linux) [ITALIANO]

Questa documentazione descrive i passaggi tecnici necessari per compilare, patchare e installare HealthyIG in un ambiente Linux o WSL (Windows Subsystem for Linux).

---

## 1. Requisiti di Sistema

Assicurarsi che i seguenti pacchetti siano installati nel proprio ambiente Linux:

```bash
sudo apt update
sudo apt install apktool zipalign apksigner default-jdk git python3-pip -y


```

Per abilitare la visualizzazione della barra di avanzamento durante l'esecuzione dello script, installare il modulo Python `tqdm`:

```bash
pip3 install tqdm


```

---

## 2. Acquisizione dell'APK Originale

Scaricare l'APK sorgente di Instagram da una fonte verificata (es. APKMirror) rispettando i seguenti vincoli tecnici:

- **Architettura:** `arm64-v8a` (standard per dispositivi Android moderni).
- **DPI:** `nodpi` (necessario per garantire la corretta decompilazione delle risorse).
- **Formato:** `APK` (i formati Bundle o APKM non sono supportati da `apktool`).

Rinominare il file scaricato in `ig.apk` e posizionarlo nella directory principale del progetto.

---

Nota per utenti WSL: I tuoi file di Windows si trovano solitamente in `/mnt/c/Users/TuoNomeUtente/Downloads/`.

---

## 3. Configurazione dell'Ambiente e Fix dello Script

Per evitare errori di esecuzione dovuti alla compatibilità tra i file system Windows e Linux, è necessario sanitizzare lo script di patch:

```bash
# Conversione dei caratteri di fine riga da CRLF a LF
sed -i 's/\r$//' script.sh

# Correzione dell'interprete xargs per la gestione dei caratteri speciali (apostrofi)
sed -i 's/xargs/xargs -d "\\n"/g' script.sh

# Assegnazione dei permessi di esecuzione
chmod +x script.sh


```

---

## 4. Procedura di Build

Eseguire i comandi nell'ordine indicato per generare il pacchetto modificato:

1. **Decompilazione:**
   `apktool d -r -f -o ig_plain ig.apk`
2. **Applicazione della Patch:**
   `./script.sh`
3. **Compilazione:**
   `apktool b -r -f ig_plain`
4. **Allineamento Risorse:**
   `zipalign -v 4 ig_plain/dist/ig.apk install.apk`

---

## 5. Generazione della Chiave e Firma Digitale

Android richiede che il pacchetto sia firmato digitalmente. I comandi seguenti generano una chiave e applicano la firma per garantire la compatibilità con i dispositivi attuali.

### Generazione Keystore:

```bash
keytool -genkeypair -v -keystore healthyig.jks -alias key0 -keyalg RSA -keysize 2048 -validity 10000 -storepass password -keypass password -dname "CN=HealthyIG, O=Android, C=IT"


```

### Apposizione della Firma:

```bash
apksigner sign --ks ./healthyig.jks --ks-pass pass:password --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --min-sdk-version 21 install.apk


```

## 6. Installazione

Rimuovere preventivamente l'applicazione Instagram ufficiale dal dispositivo (inclusi eventuali profili "App Gemelle" o "Area Personale"). Per l'installazione del nuovo pacchetto `install.apk`, procedere con una delle seguenti modalità:

### Opzione A: Trasferimento e installazione manuale (Consigliato)

Questa procedura è indicata se non si dispone di un ambiente ADB configurato su Windows.

1. **Trasferimento:** Inviare il file `install.apk` al dispositivo mobile utilizzando strumenti di trasferimento file (es. **LocalSend**, Telegram, o collegamento via cavo MTP).
2. **Autorizzazioni:** Individuare il file tramite un File Manager sul dispositivo e avviarlo. Se richiesto, autorizzare il sistema all'installazione da "Sorgenti sconosciute" per l'applicazione utilizzata.
3. **Play Protect:** Qualora Google Play Protect segnalasse l'app come non verificata, selezionare "Altre informazioni" e procedere con "Installa comunque".

### Opzione B: Tramite ADB (Android Debug Bridge)

Indicato per l'installazione diretta da terminale e per il monitoraggio di eventuali errori di sistema.

1. Abilitare le **Opzioni Sviluppatore** e il **Debug USB** sul dispositivo.
2. Collegare il dispositivo al PC e verificare la connessione tramite `adb devices`.
3. Eseguire il comando di installazione:

```powershell
adb install -r install.apk


```

---

## 7. Risoluzione dei Problemi

| Errore                            | Causa                                            | Soluzione                                                              |
| --------------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------- |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Architettura APK incompatibile con la CPU.       | Scaricare la variante `arm64-v8a`.                                     |
| `App non installata`              | Conflitto di firma o residui dell'app originale. | Disinstallare Instagram per tutti gli utenti e verificare la firma V1. |
| `/bin/bash^M: bad interpreter`    | Formato file Windows (CRLF).                     | Eseguire il comando `sed` descritto al punto 3.                        |

---
