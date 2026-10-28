#requires -Version 5.1
$ErrorActionPreference = "Stop"

# ==========================================
# KONFIGURASI
# ==========================================
$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"
$InstallDir = "$env:ProgramFiles\SmartPLS 4"
$WorkDir    = "$env:TEMP\SmartPLSInstaller"
$ZipFile    = Join-Path $WorkDir "pls.zip"

# Registry aplikasi
$UninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"

# ==========================================
# PERIKSA HAK ADMINISTRATOR
# ==========================================
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "Jalankan PowerShell sebagai Administrator." -ForegroundColor Yellow
    exit 1
}

# ==========================================
# FUNGSI: DETEKSI SMARTPLS 4 DARI REGISTRY
# ==========================================
function Get-InstalledSmartPLS {

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $InstalledApps = foreach ($Path in $RegistryPaths) {

        Get-ItemProperty `
            -Path $Path `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^SmartPLS\s*4(\s|$)"
            }
    }

    return @($InstalledApps)
}

# ==========================================
# FUNGSI: UNINSTALL SMARTPLS LAMA
# ==========================================
function Uninstall-OldSmartPLS {

    Write-Host "`n====================================" -ForegroundColor Cyan
    Write-Host "PEMERIKSAAN SMARTPLS LAMA" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

    $InstalledApps = @(Get-InstalledSmartPLS)

    if ($InstalledApps.Count -eq 0) {

        Write-Host "SmartPLS 4 tidak ditemukan di registry." -ForegroundColor Gray
        Write-Host "Melanjutkan instalasi baru..." -ForegroundColor Green

        return
    }

    foreach ($App in $InstalledApps) {

        Write-Host "`nAplikasi ditemukan:" -ForegroundColor Yellow
        Write-Host "Nama      : $($App.DisplayName)"
        Write-Host "Versi     : $($App.DisplayVersion)"
        Write-Host "Publisher  : $($App.Publisher)"
        Write-Host "Lokasi    : $($App.InstallLocation)"

        # Prioritaskan QuietUninstallString
        $UninstallString = $App.QuietUninstallString

        if ([string]::IsNullOrWhiteSpace($UninstallString)) {
            $UninstallString = $App.UninstallString
        }

        if ([string]::IsNullOrWhiteSpace($UninstallString)) {

            Write-Host "Uninstaller tidak tersedia." -ForegroundColor Yellow
            continue
        }

        Write-Host "`nMenjalankan uninstall SmartPLS lama..." -ForegroundColor Cyan

        # ==========================================
        # MSI INSTALLER
        # ==========================================
        if ($UninstallString -match "msiexec") {

            $ProductCode = [regex]::Match(
                $UninstallString,
                "\{[A-Fa-f0-9-]+\}"
            ).Value

            if (-not $ProductCode) {
                throw "ProductCode MSI tidak ditemukan."
            }

            $Process = Start-Process `
                -FilePath "msiexec.exe" `
                -ArgumentList @(
                    "/x"
                    $ProductCode
                    "/qn"
                    "/norestart"
                ) `
                -Wait `
                -PassThru
        }
        else {

            # ==========================================
            # EXE INSTALLER
            # ==========================================
            # Jalankan command uninstall dari registry.
            # QuietUninstallString digunakan jika tersedia.

            $Process = Start-Process `
                -FilePath $env:ComSpec `
                -ArgumentList @(
                    "/d"
                    "/s"
                    "/c"
                    "`"$UninstallString`""
                ) `
                -Wait `
                -PassThru
        }

        # ==========================================
        # PERIKSA HASIL UNINSTALL
        # ==========================================
        if ($Process.ExitCode -notin @(0, 1605, 3010)) {

            throw "Uninstall gagal. Exit code: $($Process.ExitCode)"

        }

        if ($Process.ExitCode -eq 3010) {

            Write-Host "Uninstall selesai. Restart Windows mungkin diperlukan." -ForegroundColor Yellow

        }
        else {

            Write-Host "Uninstall selesai." -ForegroundColor Green

        }
    }

    Write-Host "`nPemeriksaan instalasi lama selesai." -ForegroundColor Green
}

# ==========================================
# PROSES INSTALASI
# ==========================================
try {

    # ==========================================
    # 1. UNINSTALL SMARTPLS LAMA
    # ==========================================
    Uninstall-OldSmartPLS

    # ==========================================
    # 2. PERSIAPAN DOWNLOAD
    # ==========================================
    Write-Host "`n[1/5] Mengunduh SmartPLS..." -ForegroundColor Cyan

    New-Item `
        -ItemType Directory `
        -Path $WorkDir `
        -Force |
        Out-Null

    # Hapus ZIP lama
    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    # Cari curl.exe
    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue

    if (-not $Curl) {
        throw "curl.exe tidak ditemukan di Windows."
    }

    # ==========================================
    # 3. DOWNLOAD DENGAN PROGRESS BAR
    # ==========================================
    Write-Host "`nMengunduh file ZIP..." -ForegroundColor Yellow

    $CurlArgs = @(
        "-L"
        "--fail"
        "--show-error"
        "--progress-bar"
        "--retry", "5"
        "--retry-delay", "2"
        "--connect-timeout", "30"
        "--output", $ZipFile
        $DownloadURL
    )

    & $Curl.Source @CurlArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Download gagal. Exit code: $LASTEXITCODE"
    }

    if (!(Test-Path $ZipFile) -or
        (Get-Item $ZipFile).Length -eq 0) {
        throw "File ZIP gagal diunduh atau kosong."
    }

    Write-Host "`nDownload berhasil!" -ForegroundColor Green

    # ==========================================
    # 4. PERIKSA FILE ZIP
    # ==========================================
    Write-Host "`n[2/5] Memeriksa file ZIP..." -ForegroundColor Cyan

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $Archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)

    try {

        $EntryCount = $Archive.Entries.Count

        if ($EntryCount -eq 0) {
            throw "File ZIP kosong."
        }

        Write-Host "File ZIP valid. Total file: $EntryCount" -ForegroundColor Green

    }
    finally {

        $Archive.Dispose()

    }

    # ==========================================
    # 5. EKSTRAK PROGRAM
    # ==========================================
    Write-Host "`n[3/5] Mengekstrak SmartPLS..." -ForegroundColor Cyan

    New-Item `
        -ItemType Directory `
        -Path $InstallDir `
        -Force |
        Out-Null

    Expand-Archive `
        -Path $ZipFile `
        -DestinationPath $InstallDir `
        -Force

    # Cari smartpls.exe
    $Exe = Get-ChildItem `
        -Path $InstallDir `
        -Filter "smartpls.exe" `
        -File `
        -Recurse |
        Select-Object -First 1

    if (!$Exe) {
        throw "smartpls.exe tidak ditemukan. Periksa isi pls.zip."
    }

    Write-Host "Executable ditemukan: $($Exe.FullName)" -ForegroundColor Green

    # ==========================================
    # 6. BUAT SHORTCUT DESKTOP
    # ==========================================
    Write-Host "`n[4/5] Membuat shortcut Desktop..." -ForegroundColor Cyan

    $Desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")

    $Shell = New-Object -ComObject WScript.Shell

    $ShortcutPath = "$Desktop\SmartPLS 4.lnk"

    $Shortcut = $Shell.CreateShortcut($ShortcutPath)

    $Shortcut.TargetPath = $Exe.FullName
    $Shortcut.WorkingDirectory = $Exe.DirectoryName
    $Shortcut.Arguments = ""

    $Shortcut.Save()

    # Aktifkan RunAs pada shortcut
    $Bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)

    $Bytes[21] = $Bytes[21] -bor 0x20

    [System.IO.File]::WriteAllBytes(
        $ShortcutPath,
        $Bytes
    )

    Write-Host "Shortcut berhasil dibuat." -ForegroundColor Green

    # ==========================================
    # 7. BUAT UNINSTALLER POWERSHELL
    # ==========================================
    Write-Host "`nMembuat uninstaller..." -ForegroundColor Cyan

    $UninstallerPath = Join-Path $InstallDir "Uninstall-SmartPLS4.ps1"

    $UninstallerCode = @'
$ErrorActionPreference = "Stop"

$InstallDir = "$env:ProgramFiles\SmartPLS 4"
$UninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"
$ShortcutPath = "$([Environment]::GetFolderPath('CommonDesktopDirectory'))\SmartPLS 4.lnk"

# Tutup proses SmartPLS
Get-Process -Name "smartpls" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# Hapus shortcut
if (Test-Path $ShortcutPath) {
    Remove-Item $ShortcutPath -Force
}

# Hapus registry aplikasi
if (Test-Path $UninstallKey) {
    Remove-Item $UninstallKey -Recurse -Force
}

# Hapus folder instalasi
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

Write-Host "SmartPLS 4 berhasil di-uninstall." -ForegroundColor Green
'@

    Set-Content `
        -Path $UninstallerPath `
        -Value $UninstallerCode `
        -Encoding UTF8

    # ==========================================
    # 8. REGISTRASI SMARTPLS KE WINDOWS
    # ==========================================
    Write-Host "`nMendaftarkan SmartPLS ke Installed apps..." -ForegroundColor Cyan

    New-Item -Path $UninstallKey -Force | Out-Null

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "DisplayName" `
        -Value "SmartPLS 4"

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "DisplayVersion" `
        -Value "4"

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "Publisher" `
        -Value "SmartPLS"

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "InstallLocation" `
        -Value $InstallDir

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "DisplayIcon" `
        -Value $Exe.FullName

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "NoModify" `
        -Value 1 `
        -Type DWord

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "NoRepair" `
        -Value 1 `
        -Type DWord

    # Perintah uninstall yang terdaftar di Windows
    $UninstallCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$UninstallerPath`""

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "UninstallString" `
        -Value $UninstallCommand

    Set-ItemProperty `
        -Path $UninstallKey `
        -Name "QuietUninstallString" `
        -Value $UninstallCommand

    Write-Host "SmartPLS berhasil didaftarkan ke Windows." -ForegroundColor Green

    # ==========================================
    # 9. JALANKAN SMARTPLS
    # ==========================================
    Write-Host "`n[5/5] Menjalankan SmartPLS..." -ForegroundColor Cyan

    Start-Process `
        -FilePath $Exe.FullName `
        -WorkingDirectory $Exe.DirectoryName `
        -Verb RunAs

    # ==========================================
    # SELESAI
    # ==========================================
    Write-Host "`n====================================" -ForegroundColor Green
    Write-Host "INSTALASI SELESAI" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green

    Write-Host "Lokasi      : $InstallDir"
    Write-Host "Executable  : $($Exe.FullName)"
    Write-Host "Shortcut    : Desktop\SmartPLS 4.lnk"
    Write-Host "Uninstaller : $UninstallerPath"
    Write-Host "Status      : SmartPLS dijalankan sebagai Administrator."
    Write-Host "Installed apps: SmartPLS 4"

}
catch {

    Write-Host "`nINSTALASI GAGAL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1

}
