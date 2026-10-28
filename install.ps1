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

# ==========================================
# FUNGSI: CARI SMARTPLS YANG TERINSTAL
# ==========================================
function Get-InstalledSmartPLS {

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $InstalledApps = foreach ($Path in $RegistryPaths) {

        Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^SmartPLS\s*4(\s|$)"
            }
    }

    return $InstalledApps
}

# ==========================================
# FUNGSI: UNINSTALL SMARTPLS LAMA
# ==========================================
function Uninstall-OldSmartPLS {

    Write-Host "`nMemeriksa instalasi SmartPLS 4 sebelumnya..." -ForegroundColor Cyan

    $InstalledApps = @(Get-InstalledSmartPLS)

    # Deteksi instalasi dari registry
    if ($InstalledApps.Count -gt 0) {

        foreach ($App in $InstalledApps) {

            Write-Host "`nAplikasi ditemukan:" -ForegroundColor Yellow
            Write-Host "Nama       : $($App.DisplayName)"
            Write-Host "Versi      : $($App.DisplayVersion)"
            Write-Host "Publisher   : $($App.Publisher)"

            # Gunakan perintah uninstall dari registry
            $UninstallString = $App.QuietUninstallString

            if ([string]::IsNullOrWhiteSpace($UninstallString)) {
                $UninstallString = $App.UninstallString
            }

            if (![string]::IsNullOrWhiteSpace($UninstallString)) {

                Write-Host "`nMenjalankan uninstall SmartPLS lama..." -ForegroundColor Cyan

                # Deteksi Windows Installer MSI
                if ($UninstallString -match "msiexec") {

                    $ProductCode = [regex]::Match(
                        $UninstallString,
                        "\{[A-Fa-f0-9-]+\}"
                    ).Value

                    if ($ProductCode) {

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

                        # Jalankan uninstall MSI sesuai registry
                        $Process = Start-Process `
                            -FilePath "cmd.exe" `
                            -ArgumentList @(
                                "/c"
                                $UninstallString
                            ) `
                            -Wait `
                            -PassThru
                    }

                }
                else {

                    # Uninstaller EXE
                    # Gunakan QuietUninstallString jika tersedia
                    $UninstallExe = $null
                    $UninstallArgs = ""

                    if ($UninstallString -match '^\s*"([^"]+)"\s*(.*)$') {

                        $UninstallExe = $Matches[1]
                        $UninstallArgs = $Matches[2]

                    }
                    else {

                        $FirstSpace = $UninstallString.IndexOf(" ")

                        if ($FirstSpace -gt 0) {

                            $UninstallExe = $UninstallString.Substring(
                                0,
                                $FirstSpace
                            )

                            $UninstallArgs = $UninstallString.Substring(
                                $FirstSpace + 1
                            )

                        }
                        else {

                            $UninstallExe = $UninstallString

                        }
                    }

                    if (Test-Path $UninstallExe) {

                        $Process = Start-Process `
                            -FilePath $UninstallExe `
                            -ArgumentList $UninstallArgs `
                            -Wait `
                            -PassThru

                    }
                    else {

                        Write-Host "Uninstaller tidak ditemukan." -ForegroundColor Yellow

                    }
                }

                if ($Process -and $Process.ExitCode -ne 0) {
                    throw "Uninstall gagal. Exit code: $($Process.ExitCode)"
                }

                Write-Host "Uninstall selesai." -ForegroundColor Green

            }
            else {

                Write-Host "Tidak ditemukan perintah uninstall di registry." -ForegroundColor Yellow

            }
        }
    }
    else {

        Write-Host "SmartPLS 4 tidak ditemukan di registry." -ForegroundColor Gray

    }

    # ==========================================
    # DETEKSI FOLDER INSTALASI LAMA
    # ==========================================
    if (Test-Path $InstallDir) {

        Write-Host "`nMenghapus folder instalasi lama..." -ForegroundColor Cyan

        # Tutup proses SmartPLS jika sedang berjalan
        Get-Process -Name "smartpls" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        # Hapus folder instalasi
        Remove-Item `
            -Path $InstallDir `
            -Recurse `
            -Force

        Write-Host "Folder instalasi lama berhasil dihapus." -ForegroundColor Green

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
    Write-Host "`n====================================" -ForegroundColor Cyan
    Write-Host "PEMERIKSAAN SMARTPLS LAMA" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan

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
    # 7. JALANKAN SMARTPLS
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
