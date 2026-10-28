#requires -Version 5.1
$ErrorActionPreference = "Stop"

# ==========================================
# KONFIGURASI
# ==========================================
$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"
$InstallDir = "$env:ProgramFiles\SmartPLS 4"
$WorkDir = "$env:TEMP\SmartPLSInstaller"
$ZipFile = Join-Path $WorkDir "pls.zip"

# ==========================================
# PERIKSA HAK ADMINISTRATOR
# ==========================================
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Jalankan PowerShell sebagai Administrator." -ForegroundColor Yellow
    exit 1
}

try {
    # ==========================================
    # 1. UNDUH FILE (Kecepatan penuh seperti browser)
    # ==========================================
    Write-Host "`n[1/5] Mengunduh SmartPLS..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

    # Menggunakan WebClient agar kecepatan unduh optimal seperti di browser
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($DownloadURL, $ZipFile)
    $WebClient.Dispose()

    if (!(Test-Path $ZipFile) -or (Get-Item $ZipFile).Length -eq 0) {
        throw "File ZIP gagal diunduh atau kosong."
    }

    # ==========================================
    # 2. PERIKSA FILE ZIP
    # ==========================================
    Write-Host "[2/5] Memeriksa file ZIP..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
    $Archive.Dispose()

    # ==========================================
    # 3. EKSTRAK PROGRAM
    # ==========================================
    Write-Host "[3/5] Mengekstrak SmartPLS..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force

    # Cari smartpls.exe
    $Exe = Get-ChildItem -Path $InstallDir -Filter "smartpls.exe" -File -Recurse | Select-Object -First 1
    if (!$Exe) {
        throw "smartpls.exe tidak ditemukan. Periksa isi pls.zip."
    }

    # ==========================================
    # 4. BUAT SHORTCUT DESKTOP
    # ==========================================
    Write-Host "[4/5] Membuat shortcut Desktop..." -ForegroundColor Cyan
    $Desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut("$Desktop\SmartPLS 4.lnk")
    $Shortcut.TargetPath = $Exe.FullName
    $Shortcut.WorkingDirectory = $Exe.DirectoryName
    $Shortcut.Arguments = ""
    $Shortcut.Save()

    # Atur shortcut agar meminta hak Administrator
    $Bytes = [System.IO.File]::ReadAllBytes("$Desktop\SmartPLS 4.lnk")
    $Bytes[21] = $Bytes[21] -bor 0x20
    [System.IO.File]::WriteAllBytes("$Desktop\SmartPLS 4.lnk", $Bytes)

    # ==========================================
    # 5. JALANKAN SMARTPLS SEBAGAI ADMIN
    # ==========================================
    Write-Host "[5/5] Menjalankan SmartPLS sebagai Administrator..." -ForegroundColor Cyan
    Start-Process -FilePath $Exe.FullName -WorkingDirectory $Exe.DirectoryName -Verb RunAs

    # ==========================================
    # SELESAI
    # ==========================================
    Write-Host "`n====================================" -ForegroundColor Green
    Write-Host "INSTALASI SELESAI" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "Lokasi       : $InstallDir"
    Write-Host "Executable   : $($Exe.FullName)"
    Write-Host "Shortcut     : Desktop\SmartPLS 4.lnk"
    Write-Host "Status       : SmartPLS telah diminta untuk berjalan sebagai Administrator."
}
catch {
    Write-Host "`nINSTALASI GAGAL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
