# ==============================================================================
# publicar_versao.ps1
#
# Automatiza o ciclo de release do BuscaPreço Totem:
#  1. Valida ferramentas necessárias (git, gh, flutter)
#  2. Atualiza versão no pubspec.yaml e lib/config/app_version.dart
#  3. Compila o APK de Release (flutter build apk --release)
#  4. Valida a geração e calcula SHA256 do binário
#  5. Commita e gera a tag Git vX.Y.Z
#  6. Envia para o GitHub (git push origin master + tag)
#  7. Publica o Release no GitHub anexando o APK via gh release create
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Versao,

    [Parameter(Position=1)]
    [string]$Notas,

    [switch]$SkipBuild,
    [switch]$SkipPush,
    [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Garante Git e GitHub CLI no PATH
$GitCmd = "C:\Program Files\Git\cmd"
$GhBin = "C:\Program Files\GitHub CLI"
foreach ($p in @($GitCmd, $GhBin)) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$p;$env:PATH"
    }
}

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }

Write-Step "1. Validando ferramentas..."
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado no PATH."
}
Write-Ok "Git detectado."

if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Warn "GitHub CLI (gh) não encontrada. O release no GitHub não poderá ser criado automaticamente."
} else {
    Write-Ok "GitHub CLI detectada."
}

# Se a versão não foi passada por parâmetro, lê a atual do pubspec.yaml
if (-not $Versao) {
    $PubspecContent = Get-Content "pubspec.yaml" -Raw
    if ($PubspecContent -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]*)') {
        $VersaoAtual = $Matches[1]
        $BuildAtual = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
        $Partes = $VersaoAtual.Split('.')
        $NovaVersaoSugerida = "$($Partes[0]).$($Partes[1]).$([int]$Partes[2] + 1)"
        $Versao = Read-Host "Informe a nova versão (Enter para $NovaVersaoSugerida)"
        if (-not $Versao) { $Versao = $NovaVersaoSugerida }
    } else {
        $Versao = Read-Host "Informe a nova versão (ex: 1.0.1)"
    }
}

$Tag = "v$Versao"
if (-not $Notas) {
    $Notas = Read-Host "Informe as notas do release (o que mudou)"
    if (-not $Notas) { $Notas = "Atualização do BuscaPreço $Tag" }
}

Write-Step "2. Atualizando arquivos de versão para $Versao ($Tag)..."

# 1. pubspec.yaml
$PubspecPath = "pubspec.yaml"
$PubspecContent = Get-Content $PubspecPath -Raw
$BuildNum = 1
if ($PubspecContent -match 'version:\s*[0-9]+\.[0-9]+\.[0-9]+\+?([0-9]*)') {
    $BuildNum = if ($Matches[1]) { [int]$Matches[1] + 1 } else { 2 }
    $NovoPubspec = $PubspecContent -replace 'version:\s*[0-9]+\.[0-9]+\.[0-9]+\+?[0-9]*', "version: $Versao+$BuildNum"
    Set-Content -Path $PubspecPath -Value $NovoPubspec -NoNewline
    Write-Ok "pubspec.yaml atualizado para $Versao+$BuildNum."
} else {
    Write-Warn "Não foi possível atualizar automaticamente a linha de version no pubspec.yaml."
}

# 2. lib/config/app_version.dart
$AppVersionPath = "lib/config/app_version.dart"
if (Test-Path $AppVersionPath) {
    $DartLines = @(
        "/// Versão e configurações do repositório para verificação de atualização."
        "class AppVersion {"
        "  static const String version = '$Versao';"
        "  static const int buildNumber = $BuildNum;"
        ""
        "  static const String githubOwner = 'wgravinajunior-design';"
        "  static const String githubRepo = 'buscapreco';"
        ""
        "  static String get display => 'v$Versao';"
        "}"
        ""
    )
    $DartContent = $DartLines -join [Environment]::NewLine
    Set-Content -Path $AppVersionPath -Value $DartContent
    Write-Ok "lib/config/app_version.dart atualizado."
}

if (-not $SkipBuild) {
    Write-Step "3. Compilando APK de Release (flutter build apk --release)..."
    $FlutterCmd = Get-Command "flutter" -ErrorAction SilentlyContinue
    if (-not $FlutterCmd) {
        # Procura em locais comuns caso não esteja no PATH atual
        $Possiveis = @(
            "C:\src\flutter\flutter\bin\flutter.bat",
            "C:\src\flutter\bin\flutter.bat",
            "C:\flutter\bin\flutter.bat",
            "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
            "D:\src\flutter\bin\flutter.bat",
            "D:\flutter\bin\flutter.bat"
        )
        foreach ($p in $Possiveis) {
            if (Test-Path $p) {
                $FlutterCmd = $p
                break
            }
        }
    }

    if ($FlutterCmd) {
        Write-Ok "Usando Flutter em: $FlutterCmd"
        & $FlutterCmd build apk --release
        if ($LASTEXITCODE -ne 0) {
            throw "Erro durante a compilação do APK de release."
        }
        Write-Ok "APK compilado com sucesso."
    } else {
        Write-Warn "Comando 'flutter' não encontrado no PATH. Pulando compilação automática."
        Write-Host "Certifique-se de que o APK de release foi gerado previamente."
    }
}

# Localiza o APK
$ApkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $ApkPath)) {
    $ApkPath = "build\app\outputs\apk\release\app-release.apk"
}

$ApkSizeMb = 0
$Sha256 = ""
if (-not (Test-Path $ApkPath)) {
    Write-Warn "APK de release não encontrado em $ApkPath. Não será possível anexá-lo ao release."
} else {
    $ApkItem = Get-Item $ApkPath
    $ApkSizeMb = [math]::Round($ApkItem.Length / 1MB, 2)
    $Sha256 = (Get-FileHash -Path $ApkPath -Algorithm SHA256).Hash
    Write-Ok "APK pronto: $ApkPath ($ApkSizeMb MB)"
    Write-Ok "SHA256: $Sha256"
}

Write-Step "4. Criando commit e tag Git $Tag..."
$CommitMsg = "${Tag}: ${Notas}"
& git add -A
$Status = & git status --porcelain
if ($Status) {
    & git commit -m "$CommitMsg"
}
$TagExiste = & git tag -l $Tag
if ($TagExiste) {
    & git tag -f -a $Tag -m "$CommitMsg"
} else {
    & git tag -a $Tag -m "$CommitMsg"
}
Write-Ok "Commit e tag $Tag criados com sucesso."

if (-not $SkipPush) {
    Write-Step "5. Enviando para o GitHub (git push origin master + tag)..."
    & git push origin master
    & git push origin $Tag --force
    Write-Ok "Push concluído com sucesso."
}

if (-not $SkipRelease -and (Test-Path $ApkPath)) {
    Write-Step "6. Publicando Release no GitHub..."
    $GhExe = Get-Command "gh" -ErrorAction SilentlyContinue
    if ($GhExe) {
        $CorpoLines = @(
            "$Notas",
            "",
            "### Arquivo do Totem",
            "- **APK:** app-release.apk ($ApkSizeMb MB)",
            "- **SHA256:** $Sha256"
        )
        $Corpo = [string]::Join([Environment]::NewLine, $CorpoLines)
        & gh release view $Tag 2>$null
        if ($LASTEXITCODE -eq 0) {
            & gh release upload $Tag $ApkPath --clobber
            Write-Ok "APK atualizado no Release $Tag existente no GitHub!"
        } else {
            & gh release create $Tag $ApkPath --title $Tag --notes "$Corpo"
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Release $Tag criado no GitHub e APK anexado com sucesso!"
            } else {
                Write-Warn "gh release create retornou erro ao criar release."
            }
        }
    }
}

Write-Step "PROCESSO CONCLUÍDO COM SUCESSO!"
Write-Ok "Versão: $Tag"
if (Test-Path $ApkPath) {
    Write-Ok "APK: $ApkPath"
}
