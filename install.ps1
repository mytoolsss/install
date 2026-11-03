#requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# KONFIGURASI
# ============================================================
#requires -Version 5.1
# SmartPLS 4 Installer
# Jalankan file ini dengan PowerShell. Script akan meminta hak Administrator bila diperlukan.

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

$DesktopShortcut = Join-Path `
    ([Environment]::GetFolderPath("CommonDesktopDirectory")) `
    "SmartPLS 4.lnk"

# ============================================================
# CEK / MINTA ADMINISTRATOR
# ============================================================

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
$IsAdmin = $Principal.IsInRole(
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
# FUNGSI DETEKSI INSTALASI LAMA
# ============================================================

function Get-InstalledSmartPLS {
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $UninstallPaths) {
        Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^SmartPLS\s*4(\s|$)"
            }
    }
}

# ============================================================
# FUNGSI UNINSTALL INSTALASI LAMA
# - Menjalankan uninstaller GUI (tidak memaksa mode silent)
# - Menunggu proses selesai
# - Memastikan entri uninstall lama sudah hilang
# ============================================================

function Uninstall-OldSmartPLS {
    $OldApps = @(Get-InstalledSmartPLS)

    if ($OldApps.Count -eq 0) {
        Write-Host "Tidak ditemukan instalasi SmartPLS 4 lama." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Ditemukan $($OldApps.Count) entri instalasi SmartPLS 4 lama." -ForegroundColor Yellow

    # Beberapa entri registry bisa menunjuk ke uninstaller yang sama.
    $Commands = @(
        $OldApps |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.UninstallString) } |
            Select-Object -ExpandProperty UninstallString -Unique
    )

    if ($Commands.Count -eq 0) {
        throw "Entri SmartPLS lama ditemukan, tetapi UninstallString kosong. Instalasi baru dibatalkan agar versi lama tidak tertimpa."
    }

    foreach ($UninstallCommand in $Commands) {
        Write-Host ""
        Write-Host "Perintah uninstall terdeteksi:" -ForegroundColor Cyan
        Write-Host $UninstallCommand

        # MSI: ubah /I atau /X menjadi /x dan tampilkan UI uninstall.
        if ($UninstallCommand -match '(?i)msiexec(?:\.exe)?') {
            $ProductCode = [regex]::Match(
                $UninstallCommand,
                '\{[A-Fa-f0-9-]{36}\}'
            ).Value

            if (-not $ProductCode) {
                $ProductCode = @($OldApps | Where-Object {
                    $_.PSChildName -match '^\{[A-Fa-f0-9-]{36}\}$'
                } | Select-Object -ExpandProperty PSChildName -First 1)
            }

            if (-not $ProductCode) {
                throw "Product Code MSI tidak ditemukan. Uninstall dibatalkan."
            }

            Write-Host "Membuka Windows Installer untuk uninstall..." -ForegroundColor Cyan
            $Process = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/x $ProductCode /norestart" `
                -Wait -PassThru
        }
        else {
            # Pisahkan path EXE dan argumen tanpa menjalankan melalui cmd.exe.
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

            Write-Host "Membuka uninstaller SmartPLS..." -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace($Arguments)) {
                $Process = Start-Process -FilePath $ExePath -Wait -PassThru
            }
            else {
                $Process = Start-Process -FilePath $ExePath `
                    -ArgumentList $Arguments `
                    -Wait -PassThru
            }
        }

        if ($null -ne $Process -and $null -ne $Process.ExitCode) {
            Write-Host "Exit code uninstall: $($Process.ExitCode)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 3

    $Remaining = @(Get-InstalledSmartPLS)
    if ($Remaining.Count -gt 0) {
        Write-Host ""
        Write-Host "Entri instalasi lama masih ditemukan:" -ForegroundColor Red
        $Remaining | ForEach-Object { Write-Host " - $($_.DisplayName)" }
        throw "Uninstall belum terkonfirmasi berhasil. Instalasi baru dihentikan."
    }

    Write-Host "Instalasi lama berhasil dihapus / tidak lagi terdaftar." -ForegroundColor Green
}

# ============================================================
# PROSES INSTALLER
# ============================================================

try {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "          SMARTPLS 4 INSTALLER" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    # Uninstall versi lama terlebih dahulu.
    Uninstall-OldSmartPLS

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

    # Selesai.
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "      SMARTPLS 4 BERHASIL DIINSTAL" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Menjalankan SmartPLS 4..." -ForegroundColor Cyan

    # Jalankan aplikasi tanpa memaksa RunAs.
    Start-Process -FilePath $ExePath

    exit 0
}
catch {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "             INSTALLER GAGAL" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"

$InstallDir = Join-Path $env:ProgramFiles "SmartPLS 4"
$WorkDir    = Join-Path $env:TEMP "SmartPLSInstaller"
$ZipFile    = Join-Path $WorkDir "pls.zip"

$AppName   = "SmartPLS 4"
$Publisher = "SmartPLS GmbH"

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"

$DesktopShortcut = Join-Path `
    ([Environment]::GetFolderPath("CommonDesktopDirectory")) `
    "SmartPLS 4.lnk"

# ============================================================
# CEK ADMINISTRATOR
# ============================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {

    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

# ============================================================
# DETEKSI INSTALASI SMARTPLS 4 SEBELUMNYA
# ============================================================

function Get-InstalledSmartPLS {

    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($Path in $UninstallPaths) {

        Get-ItemProperty $Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^SmartPLS\s*4(\s|$)"
            }
    }
}

# ============================================================
# UNINSTALL INSTALASI LAMA
# ============================================================

function Uninstall-OldSmartPLS {

    $OldApps = @(Get-InstalledSmartPLS)

    foreach ($App in $OldApps) {

        Write-Host ""
        Write-Host "Ditemukan instalasi lama:" -ForegroundColor Yellow
        Write-Host $App.DisplayName

        $UninstallString = $App.UninstallString

        if ($App.PSChildName -match "^\{[A-Fa-f0-9-]+\}$") {

            $ProductCode = $App.PSChildName

            Start-Process "msiexec.exe" `
                -ArgumentList "/x $ProductCode /qn /norestart" `
                -Wait

        }
        elseif (-not [string]::IsNullOrWhiteSpace($UninstallString)) {

            Write-Host "Menjalankan uninstaller instalasi lama..."

            Start-Process "cmd.exe" `
                -ArgumentList "/d /s /c `"$UninstallString`"" `
                -Wait
        }
    }
}

# ============================================================
# PROSES INSTALLER
# ============================================================

try {

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "         SMARTPLS 4 INSTALLER" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    # --------------------------------------------------------
    # HAPUS VERSI LAMA JIKA TERDAFTAR
    # --------------------------------------------------------

    Uninstall-OldSmartPLS

    # --------------------------------------------------------
    # PERSIAPAN DOWNLOAD
    # --------------------------------------------------------

    if (-not (Test-Path $WorkDir)) {

        New-Item -ItemType Directory `
            -Path $WorkDir `
            -Force | Out-Null
    }

    if (Test-Path $ZipFile) {

        Remove-Item $ZipFile -Force
    }

    # --------------------------------------------------------
    # DOWNLOAD ZIP
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mengunduh SmartPLS 4..." -ForegroundColor Cyan

    $CurlPath = Join-Path $env:SystemRoot "System32\curl.exe"

    if (-not (Test-Path $CurlPath)) {

        throw "curl.exe tidak ditemukan."
    }

    & $CurlPath `
        -L `
        --fail `
        --show-error `
        --progress-bar `
        --retry 5 `
        --retry-delay 2 `
        --connect-timeout 30 `
        --output $ZipFile `
        $DownloadURL

    if ($LASTEXITCODE -ne 0) {

        throw "Download gagal."
    }

    # --------------------------------------------------------
    # VALIDASI FILE ZIP
    # --------------------------------------------------------

    if (-not (Test-Path $ZipFile)) {

        throw "File ZIP tidak ditemukan."
    }

    if ((Get-Item $ZipFile).Length -lt 1MB) {

        throw "File ZIP tidak valid atau terlalu kecil."
    }

    # --------------------------------------------------------
    # EKSTRAK SMARTPLS
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mengekstrak SmartPLS 4..." -ForegroundColor Cyan

    if (Test-Path $InstallDir) {

        Remove-Item $InstallDir -Recurse -Force
    }

    New-Item -ItemType Directory `
        -Path $InstallDir `
        -Force | Out-Null

    Expand-Archive `
        -Path $ZipFile `
        -DestinationPath $InstallDir `
        -Force

    # --------------------------------------------------------
    # CARI SMARTPLS.EXE
    # --------------------------------------------------------

    $Exe = Get-ChildItem `
        -Path $InstallDir `
        -Filter "smartpls.exe" `
        -Recurse `
        -File |
        Select-Object -First 1

    if (-not $Exe) {

        throw "smartpls.exe tidak ditemukan."
    }

    $ExePath = $Exe.FullName

    # --------------------------------------------------------
    # CARI UNINSTALL.EXE BAWAAN SMARTPLS
    # --------------------------------------------------------

    $Uninstaller = Get-ChildItem `
        -Path $InstallDir `
        -Filter "uninstall.exe" `
        -Recurse `
        -File |
        Select-Object -First 1

    if (-not $Uninstaller) {

        throw "uninstall.exe bawaan SmartPLS tidak ditemukan."
    }

    $UninstallerPath = $Uninstaller.FullName

    Write-Host ""
    Write-Host "Uninstaller bawaan ditemukan:" -ForegroundColor Green
    Write-Host $UninstallerPath

    # --------------------------------------------------------
    # BUAT SHORTCUT DESKTOP (Tanpa paksa RunAs)
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Membuat shortcut Desktop..." -ForegroundColor Cyan

    $WshShell = New-Object -ComObject WScript.Shell

    $Shortcut = $WshShell.CreateShortcut($DesktopShortcut)

    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = Split-Path $ExePath
    $Shortcut.IconLocation = "$ExePath,0"
    $Shortcut.Description = "SmartPLS 4"

    $Shortcut.Save()

    # --------------------------------------------------------
    # DAFTARKAN DI WINDOWS INSTALLED APPS
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mendaftarkan SmartPLS di Windows..." -ForegroundColor Cyan

    New-Item -Path $RegPath -Force | Out-Null

    Set-ItemProperty `
        -Path $RegPath `
        -Name "DisplayName" `
        -Value $AppName

    Set-ItemProperty `
        -Path $RegPath `
        -Name "DisplayVersion" `
        -Value "4"

    Set-ItemProperty `
        -Path $RegPath `
        -Name "Publisher" `
        -Value $Publisher

    Set-ItemProperty `
        -Path $RegPath `
        -Name "InstallLocation" `
        -Value $InstallDir

    Set-ItemProperty `
        -Path $RegPath `
        -Name "DisplayIcon" `
        -Value $ExePath

    Set-ItemProperty `
        -Path $RegPath `
        -Name "NoModify" `
        -Value 1 `
        -Type DWord

    Set-ItemProperty `
        -Path $RegPath `
        -Name "NoRepair" `
        -Value 1 `
        -Type DWord

    $UninstallString = "`"$UninstallerPath`""

    Set-ItemProperty `
        -Path $RegPath `
        -Name "UninstallString" `
        -Value $UninstallString

    # --------------------------------------------------------
    # SELESAI
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "     SMARTPLS 4 BERHASIL DIINSTAL" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Menjalankan SmartPLS 4..." -ForegroundColor Cyan

    Start-Process `
        -FilePath $ExePath `
        -Verb RunAs

    # Menutup jendela PowerShell/CMD secara otomatis setelah sukses
    exit 0

}
catch {

    Write-Host ""
    Write-Host "INSTALLER GAGAL:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}
finally {

    if (Test-Path $WorkDir) {

        Remove-Item $WorkDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
