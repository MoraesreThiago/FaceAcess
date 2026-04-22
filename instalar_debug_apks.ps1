param(
    [ValidateSet('porta', 'admin', 'both')]
    [string]$Flavor = 'both',

    [string]$DeviceId,

    [ValidateSet('auto', 'none', 'porta', 'admin')]
    [string]$Launch = 'auto',

    [switch]$SkipBuild,

    [switch]$SkipPubGet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempGoogleServices = New-Object System.Collections.Generic.List[string]

$flavorConfig = @{
    porta = @{
        Flavor = 'porta'
        Target = 'lib/main_porta.dart'
        PackageName = 'com.example.faceaccess.porta'
        ApkPath = 'C:\FaceAccessBuild\app\outputs\flutter-apk\app-porta-debug.apk'
        GoogleServicesPath = 'android/app/src/porta/google-services.json'
    }
    admin = @{
        Flavor = 'admin'
        Target = 'lib/main_admin.dart'
        PackageName = 'com.example.faceaccess.admin'
        ApkPath = 'C:\FaceAccessBuild\app\outputs\flutter-apk\app-admin-debug.apk'
        GoogleServicesPath = 'android/app/src/admin/google-services.json'
    }
}

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-Executable {
    param(
        [string]$CommandName,
        [string[]]$Candidates = @()
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "Nao foi possivel localizar '$CommandName'."
}

function Get-AndroidDevices {
    param([string]$AdbPath)

    $lines = & $AdbPath devices
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao consultar dispositivos via adb.'
    }

    $devices = @()
    foreach ($line in $lines) {
        if ($line -match '^(?<id>[^\s]+)\s+device$') {
            $devices += $Matches.id
        }
    }
    return ,$devices
}

function Resolve-DeviceId {
    param(
        [string]$AdbPath,
        [string]$RequestedDeviceId
    )

    if ($RequestedDeviceId) {
        return $RequestedDeviceId
    }

    $devices = @(Get-AndroidDevices -AdbPath $AdbPath)
    if ($devices.Count -eq 0) {
        throw 'Nenhum dispositivo Android conectado via adb.'
    }

    if ($devices.Count -gt 1) {
        throw "Mais de um dispositivo conectado. Informe -DeviceId. Encontrados: $($devices -join ', ')"
    }

    return $devices[0]
}

function New-FlavorGoogleServices {
    param(
        [string]$RepoRoot,
        [hashtable]$Config
    )

    $sourcePath = Join-Path $RepoRoot 'android/app/google-services.json'
    $targetPath = Join-Path $RepoRoot $Config.GoogleServicesPath

    if (-not (Test-Path $sourcePath)) {
        throw "Arquivo base google-services.json nao encontrado em '$sourcePath'."
    }

    $json = Get-Content $sourcePath -Raw | ConvertFrom-Json
    if (-not $json.client -or $json.client.Count -eq 0) {
        throw 'google-services.json base nao possui clientes Android.'
    }

    $json.client[0].client_info.android_client_info.package_name = $Config.PackageName

    $targetDir = Split-Path -Parent $targetPath
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $json | ConvertTo-Json -Depth 100 | Set-Content -Path $targetPath -Encoding UTF8

    $tempGoogleServices.Add($targetPath)
}

function Remove-TempGoogleServices {
    foreach ($path in $tempGoogleServices) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }

        $parent = Split-Path -Parent $path
        if ((Test-Path $parent) -and -not (Get-ChildItem -Force $parent | Select-Object -First 1)) {
            Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-FlutterBuild {
    param(
        [string]$FlutterPath,
        [string]$RepoRoot,
        [hashtable]$Config
    )

    $apkPath = $Config.ApkPath
    if (Test-Path $apkPath) {
        Remove-Item -LiteralPath $apkPath -Force
    }

    Write-Step "Buildando flavor '$($Config.Flavor)'"
    Push-Location $RepoRoot
    try {
        & $FlutterPath build apk --debug --flavor $Config.Flavor -t $Config.Target --android-skip-build-dependency-validation
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $apkPath)) {
        throw "Build do flavor '$($Config.Flavor)' nao gerou APK em '$apkPath'."
    }

    if ($exitCode -ne 0) {
        Write-Warning "Flutter retornou codigo $exitCode, mas o APK foi encontrado. Continuando com a instalacao."
    }
}

function Install-Apk {
    param(
        [string]$AdbPath,
        [string]$ResolvedDeviceId,
        [hashtable]$Config
    )

    Write-Step "Instalando '$($Config.Flavor)' no dispositivo $ResolvedDeviceId"
    & $AdbPath -s $ResolvedDeviceId install -r $Config.ApkPath
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar '$($Config.Flavor)' no dispositivo."
    }
}

function Launch-App {
    param(
        [string]$AdbPath,
        [string]$ResolvedDeviceId,
        [hashtable]$Config
    )

    Write-Step "Abrindo '$($Config.Flavor)' no dispositivo"
    & $AdbPath -s $ResolvedDeviceId shell monkey -p $Config.PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao abrir '$($Config.Flavor)' no dispositivo."
    }
}

try {
    Set-Location $repoRoot

    $flutterPath = Resolve-Executable -CommandName 'flutter' -Candidates @(
        'C:\flutter\bin\flutter.bat',
        'C:\flutter\flutter\bin\flutter.bat'
    )

    $adbCandidates = New-Object System.Collections.Generic.List[string]
    $adbCandidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'))
    if ($env:ANDROID_SDK_ROOT) {
        $adbCandidates.Add((Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'))
    }
    if ($env:ANDROID_HOME) {
        $adbCandidates.Add((Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'))
    }

    $adbPath = Resolve-Executable -CommandName 'adb' -Candidates $adbCandidates.ToArray()

    $resolvedDeviceId = Resolve-DeviceId -AdbPath $adbPath -RequestedDeviceId $DeviceId

    switch ($Flavor) {
        'both' {
            $selectedFlavors = @('porta', 'admin')
        }
        default {
            $selectedFlavors = @($Flavor)
        }
    }

    if ($Launch -eq 'auto') {
        if ($selectedFlavors -contains 'porta') {
            $Launch = 'porta'
        } else {
            $Launch = 'none'
        }
    }

    if (-not $SkipPubGet) {
        Write-Step 'Rodando flutter pub get'
        & $flutterPath pub get
        if ($LASTEXITCODE -ne 0) {
            throw 'Falha ao rodar flutter pub get.'
        }
    }

    foreach ($selectedFlavor in $selectedFlavors) {
        New-FlavorGoogleServices -RepoRoot $repoRoot -Config $flavorConfig[$selectedFlavor]
    }

    foreach ($selectedFlavor in $selectedFlavors) {
        $config = $flavorConfig[$selectedFlavor]
        if (-not $SkipBuild) {
            Invoke-FlutterBuild -FlutterPath $flutterPath -RepoRoot $repoRoot -Config $config
        }
        Install-Apk -AdbPath $adbPath -ResolvedDeviceId $resolvedDeviceId -Config $config
    }

    if ($Launch -ne 'none') {
        Launch-App -AdbPath $adbPath -ResolvedDeviceId $resolvedDeviceId -Config $flavorConfig[$Launch]
    }

    Write-Host ''
    Write-Host "Instalacao concluida no dispositivo $resolvedDeviceId." -ForegroundColor Green
    foreach ($selectedFlavor in $selectedFlavors) {
        Write-Host " - $selectedFlavor => $($flavorConfig[$selectedFlavor].ApkPath)"
    }
} finally {
    Remove-TempGoogleServices
}
