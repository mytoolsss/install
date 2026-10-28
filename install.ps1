#requires -Version 5.1

# ============================================================
# SmartPLS 4 Installer
# PowerShell + Windows Forms
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# KONFIGURASI
# ============================================================

$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"

$InstallDir = Join-Path $env:ProgramFiles "SmartPLS 4"
$WorkDir    = Join-Path $env:TEMP "SmartPLSInstaller"
$ZipFile   = Join-Path $WorkDir "pls.zip"

$AppName   = "SmartPLS 4"
$Publisher = "SmartPLS"
$RegPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"

$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "SmartPLS 4.lnk"

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
# FUNGSI DETEKSI INSTALASI LAMA
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
# FUNGSI UNINSTALL VERSI LAMA
# ============================================================

function Uninstall-OldSmartPLS {

    $OldApps = @(Get-InstalledSmartPLS)

    foreach ($App in $OldApps) {

        Write-Host "Menghapus instalasi lama: $($App.DisplayName)" `
            -ForegroundColor Yellow

        $UninstallString = $App.QuietUninstallString

        if ([string]::IsNullOrWhiteSpace($UninstallString)) {
            $UninstallString = $App.UninstallString
        }

        if ($App.PSChildName -match "^\{[A-Fa-f0-9-]+\}$") {

            $ProductCode = $App.PSChildName

            Start-Process "msiexec.exe" `
                -ArgumentList "/x $ProductCode /qn /norestart" `
                -Wait

        }
        elseif (-not [string]::IsNullOrWhiteSpace($UninstallString)) {

            Start-Process "cmd.exe" `
                -ArgumentList "/d /s /c `"$UninstallString`"" `
                -Wait
        }
    }
}

# ============================================================
# FUNGSI MEMBUAT UNINSTALLER GUI
# ============================================================

function Create-Uninstaller {

    $UninstallerPath = Join-Path $InstallDir "Uninstall-SmartPLS4.ps1"

    $UninstallerCode = @'
#requires -Version 5.1

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$InstallDir = "$env:ProgramFiles\SmartPLS 4"
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"

$DesktopShortcut = Join-Path `
    ([Environment]::GetFolderPath("CommonDesktopDirectory")) `
    "SmartPLS 4.lnk"

# ------------------------------------------------------------
# GUI
# ------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form

$form.Text = "Uninstall SmartPLS 4"
$form.Size = New-Object System.Drawing.Size(520, 285)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

$title = New-Object System.Windows.Forms.Label
$title.Text = "Uninstall SmartPLS 4"
$title.Font = New-Object System.Drawing.Font(
    "Segoe UI", 16, [System.Drawing.FontStyle]::Bold
)
$title.Location = New-Object System.Drawing.Point(25, 20)
$title.Size = New-Object System.Drawing.Size(450, 35)

$description = New-Object System.Windows.Forms.Label
$description.Text = "Aplikasi dan file SmartPLS 4 akan dihapus dari komputer."
$description.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$description.Location = New-Object System.Drawing.Point(27, 65)
$description.Size = New-Object System.Drawing.Size(450, 25)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Siap menghapus SmartPLS 4."
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$status.Location = New-Object System.Drawing.Point(27, 115)
$status.Size = New-Object System.Drawing.Size(450, 25)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(27, 145)
$progress.Size = New-Object System.Drawing.Size(450, 22)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Style = "Continuous"

$button = New-Object System.Windows.Forms.Button
$button.Text = "Uninstall"
$button.Location = New-Object System.Drawing.Point(350, 190)
$button.Size = New-Object System.Drawing.Size(125, 32)

$form.Controls.AddRange(@(
    $title,
    $description,
    $status,
    $progress,
    $button
))

# ------------------------------------------------------------
# TIMER
# ------------------------------------------------------------

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100

$script:Step = 0
$script:Busy = $false

$timer.Add_Tick({

    $script:Step += 5

    if ($script:Step -gt 100) {
        $script:Step = 100
    }

    $progress.Value = $script:Step

    switch ($script:Step) {

        10 {
            $status.Text = "Menutup SmartPLS 4..."
            Get-Process -Name "smartpls" -ErrorAction SilentlyContinue |
                Stop-Process -Force
        }

        30 {
            $status.Text = "Menghapus shortcut..."
            Remove-Item $DesktopShortcut -Force
        }

        50 {
            $status.Text = "Membersihkan registry..."
            Remove-Item $RegPath -Recurse -Force
        }

        70 {
            $status.Text = "Menyiapkan penghapusan file..."
        }

        90 {
            $status.Text = "Menyelesaikan proses uninstall..."
        }
    }

    if ($script:Step -ge 100) {

        $timer.Stop()

        $status.Text = "SmartPLS 4 berhasil dihapus."
        $button.Text = "Selesai"
        $button.Enabled = $true

        # Jalankan penghapusan folder setelah script ini keluar.
        # Ini menghindari masalah menghapus file uninstaller yang
        # sedang digunakan.
        $cmd = 'cmd.exe /c timeout /t 2 /nobreak >nul & rmdir /s /q "{0}"' -f $InstallDir

        Start-Process "cmd.exe" `
            -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$InstallDir`"" `
            -WindowStyle Hidden

        $script:Busy = $false
    }
})

# ------------------------------------------------------------
# TOMBOL
# ------------------------------------------------------------

$button.Add_Click({

    if ($script:Step -ge 100) {
        $form.Close()
        return
    }

    if (-not $script:Busy) {

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apakah Anda yakin ingin menghapus SmartPLS 4?",
            "Konfirmasi Uninstall",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {

            $script:Busy = $true
            $button.Enabled = $false
            $button.Text = "Menghapus..."

            $timer.Start()
        }
    }
})

$form.Add_FormClosing({

    if ($script:Busy -and $script:Step -lt 100) {

        [System.Windows.Forms.MessageBox]::Show(
            "Tunggu hingga proses uninstall selesai.",
            "Uninstall SmartPLS 4"
        )

        $_.Cancel = $true
    }
})

[void]$form.ShowDialog()
'@

    Set-Content `
        -Path $UninstallerPath `
        -Value $UninstallerCode `
        -Encoding UTF8

    return $UninstallerPath
}

# ============================================================
# PROSES INSTALLER
# ============================================================

try {

    Write-Host ""
    Write-Host "==========================================" `
        -ForegroundColor Cyan

    Write-Host "       SMARTPLS 4 INSTALLER" `
        -ForegroundColor Cyan

    Write-Host "==========================================" `
        -ForegroundColor Cyan

    # --------------------------------------------------------
    # HAPUS VERSI LAMA
    # --------------------------------------------------------

    Uninstall-OldSmartPLS

    # --------------------------------------------------------
    # PERSIAPAN DOWNLOAD
    # --------------------------------------------------------

    if (-not (Test-Path $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }

    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    # --------------------------------------------------------
    # DOWNLOAD
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mengunduh SmartPLS 4..." -ForegroundColor Cyan

    $CurlPath = Join-Path $env:SystemRoot "System32\curl.exe"

    if (-not (Test-Path $CurlPath)) {
        throw "curl.exe tidak ditemukan di Windows."
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
        throw "Download gagal. Periksa koneksi internet atau URL."
    }

    # --------------------------------------------------------
    # VALIDASI ZIP
    # --------------------------------------------------------

    if (-not (Test-Path $ZipFile)) {
        throw "File ZIP tidak ditemukan."
    }

    if ((Get-Item $ZipFile).Length -lt 1MB) {
        throw "File ZIP terlalu kecil atau download tidak valid."
    }

    # --------------------------------------------------------
    # EKSTRAK
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mengekstrak file SmartPLS 4..." `
        -ForegroundColor Cyan

    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $InstallDir -Force |
        Out-Null

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
        throw "smartpls.exe tidak ditemukan setelah ekstraksi."
    }

    $ExePath = $Exe.FullName

    # --------------------------------------------------------
    # BUAT SHORTCUT DESKTOP
    # --------------------------------------------------------

    Write-Host "Membuat shortcut Desktop..." -ForegroundColor Cyan

    $WshShell = New-Object -ComObject WScript.Shell

    $Shortcut = $WshShell.CreateShortcut($DesktopShortcut)

    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = Split-Path $ExePath
    $Shortcut.IconLocation = "$ExePath,0"
    $Shortcut.Description = "SmartPLS 4"

    $Shortcut.Save()

    # --------------------------------------------------------
    # BUAT UNINSTALLER GUI
    # --------------------------------------------------------

    Write-Host "Membuat uninstaller GUI..." -ForegroundColor Cyan

    $UninstallerPath = Create-Uninstaller

    # --------------------------------------------------------
    # DAFTARKAN DI WINDOWS INSTALLED APPS
    # --------------------------------------------------------

    Write-Host "Mendaftarkan SmartPLS 4 di Windows..." `
        -ForegroundColor Cyan

    New-Item -Path $RegPath -Force | Out-Null

    Set-ItemProperty `
        -Path $RegPath `
        -Name "DisplayName" `
        -Value "SmartPLS 4"

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

    # Uninstall berjalan tersembunyi, tetapi GUI uninstaller tampil.
    $UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$UninstallerPath`""

    Set-ItemProperty `
        -Path $RegPath `
        -Name "UninstallString" `
        -Value $UninstallString

    Set-ItemProperty `
        -Path $RegPath `
        -Name "QuietUninstallString" `
        -Value $UninstallString

    # --------------------------------------------------------
    # SELESAI
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "==========================================" `
        -ForegroundColor Green

    Write-Host "SmartPLS 4 berhasil diinstal!" `
        -ForegroundColor Green

    Write-Host "==========================================" `
        -ForegroundColor Green

    # --------------------------------------------------------
    # JALANKAN SMARTPLS
    # --------------------------------------------------------

    Write-Host "Menjalankan SmartPLS 4..." `
        -ForegroundColor Cyan

    Start-Process -FilePath $ExePath

}
catch {

    Write-Host ""
    Write-Host "INSTALLER GAGAL:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}
finally {

    # Bersihkan file download sementara.
    if (Test-Path $WorkDir) {
        Remove-Item $WorkDir -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}
