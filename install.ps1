#requires -Version 5.1
# SmartPLS 4 Installer - multi-install cleanup (C:, D:, etc.)
# Jalankan file .ps1 ini. Script akan meminta hak Administrator bila diperlukan.

$ErrorActionPreference = "Stop"

# ============================================================
# KONFIGURASI
# ============================================================

$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"

$InstallDir = Join-Path $env:ProgramFiles "SmartPLS 4"
$WorkDir    = Join-Path $env:TEMP "SmartPLSInstaller"
$ZipFile    = Join-Path $WorkDir "pls.zip"

$AppName   = "SmartPLS 4"
$Publisher = "SmartPLS GmbH"
$RegPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"

$LogFile = Join-Path $env:TEMP "SmartPLS4_Installer.log"

$DesktopShortcut = Join-Path `
    ([Environment]::GetFolderPath("CommonDesktopDirectory")) `
    "SmartPLS 4.lnk"

# ============================================================
# CEK / MINTA ADMINISTRATOR
# ============================================================

$Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
$IsAdmin   = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw "Simpan script sebagai file .ps1 terlebih dahulu, lalu jalankan kembali."
    }

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$PSCommandPath`""
    )
    exit
}

# ============================================================
# DETEKSI SEMUA ENTRI SMARTPLS 4 (SEMUA DRIVE / REGISTRY VIEW)
# ============================================================

function Get-InstalledSmartPLS {
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Found = foreach ($Path in $UninstallPaths) {
        Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^SmartPLS\s*4(\s|$)"
            }
    }

    # Dedup hanya entri registry yang benar-benar sama.
    @($Found | Sort-Object -Property PSPath -Unique)
}

function Get-SmartPLSExe {
    param([string]$InstallLocation)

    if ([string]::IsNullOrWhiteSpace($InstallLocation)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $InstallLocation -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $InstallLocation `
        -Filter "smartpls.exe" -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

# ============================================================
# JALANKAN UNINSTALLER SATU PER SATU
# ============================================================

function Invoke-SmartPLSUninstall {
    param(
        [Parameter(Mandatory = $true)]
        $App
    )

    $Name = $App.DisplayName
    $InstallLocation = [string]$App.InstallLocation
    $UninstallCommand = [string]$App.UninstallString

    Write-Host ""
    Write-Host "----------------------------------------------" -ForegroundColor Cyan
    Write-Host "Instalasi lama: $Name" -ForegroundColor Yellow
    Write-Host "Lokasi         : $InstallLocation"
    Write-Host "Registry       : $($App.PSPath)"
    Write-Host "----------------------------------------------" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($UninstallCommand)) {
        throw "UninstallString kosong untuk entri: $Name. Instalasi baru dibatalkan."
    }

    $Process = $null

    # MSI uninstall. Tidak memakai /qn agar UI uninstall dapat muncul.
    if ($UninstallCommand -match '(?i)msiexec(?:\.exe)?') {
        $ProductCode = [regex]::Match(
            $UninstallCommand,
            '\{[A-Fa-f0-9-]{36}\}'
        ).Value

        if (-not $ProductCode -and $App.PSChildName -match '^\{[A-Fa-f0-9-]{36}\}$') {
            $ProductCode = $App.PSChildName
        }

        if (-not $ProductCode) {
            throw "Product Code MSI tidak ditemukan untuk $Name."
        }

        Write-Host "Membuka Windows Installer untuk uninstall..." -ForegroundColor Cyan
        $Process = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x $ProductCode /norestart" `
            -Wait -PassThru
    }
    else {
        # Ambil executable dan argumen dari UninstallString.
        if ($UninstallCommand -match '^\s*"([^"]+\.exe)"\s*(.*)$') {
            $ExePath = $Matches[1]
            $Arguments = $Matches[2]
        }
        elseif ($UninstallCommand -match '^\s*(.+?\.exe)(?:\s+(.*))?$') {
            $ExePath = $Matches[1].Trim('"')
            $Arguments = $Matches[2]
        }
        else {
            throw "Format UninstallString tidak dikenali: $UninstallCommand"
        }

        if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
            throw "File uninstaller tidak ditemukan: $ExePath"
        }

        Write-Host "Membuka uninstaller: $ExePath" -ForegroundColor Cyan
        Write-Host "Jika jendela uninstall muncul, selesaikan sampai tuntas."

        if ([string]::IsNullOrWhiteSpace($Arguments)) {
            $Process = Start-Process -FilePath $ExePath -Wait -PassThru
        }
        else {
            $Process = Start-Process -FilePath $ExePath `
                -ArgumentList $Arguments `
                -Wait -PassThru
        }
    }

    if ($null -ne $Process) {
        Write-Host "Proses uninstall selesai. Exit code: $($Process.ExitCode)" -ForegroundColor Yellow
    }
}

# ============================================================
# UNINSTALL SEMUA INSTALASI LAMA, BUKAN HANYA SATU
# ============================================================

function Uninstall-AllOldSmartPLS {
    $OldApps = @(Get-InstalledSmartPLS)

    if ($OldApps.Count -eq 0) {
        Write-Host "Tidak ditemukan instalasi SmartPLS 4 lama." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Ditemukan $($OldApps.Count) entri SmartPLS 4." -ForegroundColor Yellow

    # Proses setiap entri registry satu per satu. Jangan dedup berdasarkan
    # UninstallString karena instalasi C: dan D: bisa berbeda.
    foreach ($App in $OldApps) {
        Invoke-SmartPLSUninstall -App $App

        Start-Sleep -Seconds 2

        # Periksa apakah aplikasi masih benar-benar ada di lokasi entri tersebut.
        $RemainingExe = Get-SmartPLSExe -InstallLocation ([string]$App.InstallLocation)

        if ($RemainingExe) {
            throw "SmartPLS masih ditemukan di '$($App.InstallLocation)'. Uninstall belum tuntas; instalasi baru dihentikan."
        }

        # Jika folder aplikasi sudah tidak memiliki smartpls.exe, entri registry
        # yang tertinggal dianggap stale dan dibersihkan agar tidak menghambat.
        if ($App.PSPath -and (Test-Path -LiteralPath $App.PSPath)) {
            Write-Host "Membersihkan entri uninstall yang tertinggal..." -ForegroundColor Yellow
            Remove-Item -LiteralPath $App.PSPath -Recurse -Force
        }

        Write-Host "Entri instalasi tersebut sudah dibersihkan." -ForegroundColor Green
    }

    # Verifikasi akhir: jangan lanjut jika masih ada aplikasi yang terdeteksi.
    $FinalEntries = @(Get-InstalledSmartPLS)
    $RealRemaining = @(
        foreach ($Entry in $FinalEntries) {
            $FoundExe = Get-SmartPLSExe -InstallLocation ([string]$Entry.InstallLocation)
            if ($FoundExe) { $Entry }
        }
    )

    if ($RealRemaining.Count -gt 0) {
        $Locations = ($RealRemaining | ForEach-Object { $_.InstallLocation }) -join ", "
        throw "SmartPLS lama masih terdeteksi di: $Locations. Instalasi baru dibatalkan."
    }

    # Hapus hanya entri registry SmartPLS yang tersisa dan sudah tidak memiliki
    # smartpls.exe pada InstallLocation-nya.
    foreach ($Entry in $FinalEntries) {
        if ($Entry.PSPath -and (Test-Path -LiteralPath $Entry.PSPath)) {
            $FoundExe = Get-SmartPLSExe -InstallLocation ([string]$Entry.InstallLocation)
            if (-not $FoundExe) {
                Remove-Item -LiteralPath $Entry.PSPath -Recurse -Force
            }
        }
    }

    Write-Host ""
    Write-Host "Pemeriksaan instalasi lama selesai." -ForegroundColor Green
}

# ============================================================
# PROSES INSTALLER
# ============================================================

try {
    Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "          SMARTPLS 4 INSTALLER" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    # Hapus seluruh instalasi lama yang terdaftar, termasuk yang berada di C: dan D:.
    Uninstall-AllOldSmartPLS

    # Persiapan folder kerja.
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

    if (Test-Path -LiteralPath $ZipFile) {
        Remove-Item -LiteralPath $ZipFile -Force
    }

    # Download.
    Write-Host ""
    Write-Host "Mengunduh SmartPLS 4..." -ForegroundColor Cyan

    $CurlPath = Join-Path $env:SystemRoot "System32\curl.exe"
    if (-not (Test-Path -LiteralPath $CurlPath)) {
        throw "curl.exe tidak ditemukan."
    }

    & $CurlPath -L --fail --show-error --progress-bar `
        --retry 5 --retry-delay 2 --connect-timeout 30 `
        --output $ZipFile $DownloadURL

    if ($LASTEXITCODE -ne 0) {
        throw "Download gagal. Kode curl: $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $ZipFile)) {
        throw "File ZIP tidak ditemukan setelah download."
    }

    if ((Get-Item -LiteralPath $ZipFile).Length -lt 1MB) {
        throw "File ZIP tidak valid atau terlalu kecil."
    }

    # Ekstrak ke folder instalasi.
    Write-Host ""
    Write-Host "Mengekstrak SmartPLS 4..." -ForegroundColor Cyan

    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Expand-Archive -LiteralPath $ZipFile -DestinationPath $InstallDir -Force

    # Cari executable.
    $Exe = Get-ChildItem -Path $InstallDir -Filter "smartpls.exe" -Recurse -File |
        Select-Object -First 1

    if (-not $Exe) {
        throw "smartpls.exe tidak ditemukan di dalam arsip."
    }

    $ExePath = $Exe.FullName

    # Cari uninstaller bawaan (bila tersedia).
    $Uninstaller = Get-ChildItem -Path $InstallDir -Filter "uninstall.exe" -Recurse -File |
        Select-Object -First 1

    # Buat shortcut desktop.
    Write-Host ""
    Write-Host "Membuat shortcut Desktop..." -ForegroundColor Cyan

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = Split-Path -Parent $ExePath
    $Shortcut.IconLocation = "$ExePath,0"
    $Shortcut.Description = "SmartPLS 4"
    $Shortcut.Save()

    # Daftarkan di Windows Installed Apps.
    Write-Host "Mendaftarkan SmartPLS di Windows..." -ForegroundColor Cyan

    New-Item -Path $RegPath -Force | Out-Null

    $RegistryValues = @{
        DisplayName     = $AppName
        DisplayVersion  = "4"
        Publisher       = $Publisher
        InstallLocation = $InstallDir
        DisplayIcon     = $ExePath
        NoModify        = 1
        NoRepair        = 1
    }

    foreach ($Name in $RegistryValues.Keys) {
        if ($Name -in @("NoModify", "NoRepair")) {
            New-ItemProperty -Path $RegPath -Name $Name `
                -Value $RegistryValues[$Name] -PropertyType DWord -Force | Out-Null
        }
        else {
            New-ItemProperty -Path $RegPath -Name $Name `
                -Value $RegistryValues[$Name] -PropertyType String -Force | Out-Null
        }
    }

    if ($Uninstaller) {
        $UninstallString = '"' + $Uninstaller.FullName + '"'
        New-ItemProperty -Path $RegPath -Name "UninstallString" `
            -Value $UninstallString -PropertyType String -Force | Out-Null
    }
    else {
        Write-Warning "uninstall.exe tidak ditemukan; entri uninstall tidak dibuat."
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "      SMARTPLS 4 BERHASIL DIINSTAL" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Menjalankan SmartPLS 4..." -ForegroundColor Cyan
    Start-Process -FilePath $ExePath
    Write-Host ""
    Write-Host "Log tersimpan di: $LogFile" -ForegroundColor Cyan
    Read-Host "Tekan ENTER untuk menutup jendela ini"
}
catch {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "             INSTALLER GAGAL" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Detail error tersimpan di: $LogFile" -ForegroundColor Yellow
    Read-Host "Tekan ENTER untuk menutup jendela ini"
}
finally {
    if (Test-Path -LiteralPath $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    try { Stop-Transcript | Out-Null } catch {}
}
