$ErrorActionPreference = "Stop"

$DownloadURL = "https://github.com/mytoolsss/install/releases/latest/download/pls.zip"
$InstallDir = Join-Path $env:ProgramFiles "SmartPLS 4"
$WorkDir    = Join-Path $env:TEMP "SmartPLSInstaller"
$ZipFile    = Join-Path $WorkDir "pls.zip"
$AppName   = "SmartPLS 4"
$Publisher = "SmartPLS GmbH"
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SmartPLS4"
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "SmartPLS 4.lnk"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Get-InstalledSmartPLS {
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($Path in $UninstallPaths) {
        Get-ItemProperty $Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "^SmartPLS\s*4(\s|$)" }
    }
}

function Uninstall-OldSmartPLS {
    $OldApps = @(Get-InstalledSmartPLS)
    foreach ($App in $OldApps) {
        Write-Host "`nDitemukan instalasi lama:" -ForegroundColor Yellow
        Write-Host $App.DisplayName
        $UninstallString = $App.UninstallString

        if ($App.PSChildName -match "^\{[A-Fa-f0-9-]+\}$") {
            $ProductCode = $App.PSChildName
            Start-Process "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait
        }
        elseif (-not [string]::IsNullOrWhiteSpace($UninstallString)) {
            Write-Host "Menjalankan uninstaller instalasi lama..."
            $ExePath = $UninstallString.Replace('"', '')
            Start-Process -FilePath $ExePath -ArgumentList "/S" -Wait
            Start-Sleep -Seconds 5
        }
    }
}

try {
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "         SMARTPLS 4 INSTALLER" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    Uninstall-OldSmartPLS

    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

    Write-Host "`nMengunduh SmartPLS 4..." -ForegroundColor Cyan
    $CurlPath = Join-Path $env:SystemRoot "System32\curl.exe"
    if (-not (Test-Path $CurlPath)) { throw "curl.exe tidak ditemukan." }

    & $CurlPath -L --fail --show-error --progress-bar --retry 5 --retry-delay 2 --connect-timeout 30 --output $ZipFile $DownloadURL
    if ($LASTEXITCODE -ne 0) { throw "Download gagal." }

    if (-not (Test-Path $ZipFile)) { throw "File ZIP tidak ditemukan." }
    if ((Get-Item $ZipFile).Length -lt 1MB) { throw "File ZIP tidak valid atau terlalu kecil." }

    Write-Host "`nMengekstrak SmartPLS 4..." -ForegroundColor Cyan
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force

    $Exe = Get-ChildItem -Path $InstallDir -Filter "smartpls.exe" -Recurse -File | Select-Object -First 1
    if (-not $Exe) { throw "smartpls.exe tidak ditemukan." }
    $ExePath = $Exe.FullName

    $Uninstaller = Get-ChildItem -Path $InstallDir -Filter "uninstall.exe" -Recurse -File | Select-Object -First 1
    if (-not $Uninstaller) { throw "uninstall.exe bawaan SmartPLS tidak ditemukan." }
    $UninstallerPath = $Uninstaller.FullName

    Write-Host "`nUninstaller bawaan ditemukan:" -ForegroundColor Green
    Write-Host $UninstallerPath

    Write-Host "`nMembuat shortcut Desktop..." -ForegroundColor Cyan
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = Split-Path $ExePath
    $Shortcut.IconLocation = "$ExePath,0"
    $Shortcut.Description = "SmartPLS 4"
    $Shortcut.Save()

    Write-Host "`nMendaftarkan SmartPLS di Windows..." -ForegroundColor Cyan
    New-Item -Path $RegPath -Force | Out-Null
    Set-ItemProperty -Path $RegPath -Name "DisplayName" -Value $AppName
    Set-ItemProperty -Path $RegPath -Name "DisplayVersion" -Value "4"
    Set-ItemProperty -Path $RegPath -Name "Publisher" -Value $Publisher
    Set-ItemProperty -Path $RegPath -Name "InstallLocation" -Value $InstallDir
    Set-ItemProperty -Path $RegPath -Name "DisplayIcon" -Value $ExePath
    Set-ItemProperty -Path $RegPath -Name "NoModify" -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name "NoRepair" -Value 1 -Type DWord
    $UninstallString = "`"$UninstallerPath`""
    Set-ItemProperty -Path $RegPath -Name "UninstallString" -Value $UninstallString

    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "     SMARTPLS 4 BERHASIL DIINSTAL" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    Write-Host "`nMenjalankan SmartPLS 4..." -ForegroundColor Cyan
    Start-Process -FilePath $ExePath -Verb RunAs
    exit 0
}
catch {
    Write-Host "`nINSTALLER GAGAL:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
