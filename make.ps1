# Windows 下的默认壳构建入口。release 只处理 sparq-app，不包含 Website 或其他二次开发应用。
param(
    [string]$Target = "help",
    [string]$GO = $(if ($env:GO) { $env:GO } else { "go" }),
    [string]$AppName = $(if ($env:APP_NAME) { $env:APP_NAME } else { "sparq" }),
    [string]$Cmd = $(if ($env:CMD) { $env:CMD } else { "./cmd/sparq" }),
    [string]$BinDir = $(if ($env:BIN_DIR) { $env:BIN_DIR } else { "bin" }),
    [string]$DistDir = $(if ($env:DIST_DIR) { $env:DIST_DIR } else { "dist" }),
    [string]$Version = $(if ($env:VERSION) { $env:VERSION } else { "dev" }),
    [string]$GOOS = $env:GOOS,
    [string]$GOARCH = $env:GOARCH,
    [string]$GoCache = $(if ($env:GOCACHE) { $env:GOCACHE } else { Join-Path $PSScriptRoot "../.cache/go-build" }),
    [string]$CGOEnabled = $(if ($env:CGO_ENABLED) { $env:CGO_ENABLED } else { "0" }),
    [string]$Tags = $(if ($env:TAGS) { $env:TAGS } else { "" }),
    [string]$LdFlags = $(if ($env:LDFLAGS) { $env:LDFLAGS } else { "" }),
    [string]$Config = $(if ($env:CONFIG) { $env:CONFIG } else { "config/app.yaml" }),
    [string]$EnvName = $(if ($env:ENV) { $env:ENV } else { "dev" }),
    [string]$Args = $(if ($env:ARGS) { $env:ARGS } else { "" }),
    [string]$Platforms = $(if ($env:PLATFORMS) { $env:PLATFORMS } else { "linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64" })
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Go-HostValue([string]$Name) {
    $value = & $GO env $Name
    if ($LASTEXITCODE -ne 0) {
        throw "go env $Name failed"
    }
    return $value.Trim()
}

if (-not $GOOS) {
    $GOOS = Go-HostValue "GOHOSTOS"
}
if (-not $GOARCH) {
    $GOARCH = Go-HostValue "GOHOSTARCH"
}
$HostGOOS = Go-HostValue "GOHOSTOS"
$HostGOARCH = Go-HostValue "GOHOSTARCH"

$ReleaseLdFlags = $LdFlags
if ($Version -ne "dev") {
    if ($ReleaseLdFlags) { $ReleaseLdFlags += " " }
    $ReleaseLdFlags += @(
        "-X github.com/zane-xin/sparq.version=v$Version",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.HostVersion=v$Version",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.Distribution=official",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.HostOwnership=managed",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.HostUpdatePolicy=automatic",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.AdminOwnership=managed",
        "-X github.com/zane-xin/sparq/internal/buildmanifest.AdminUpdatePolicy=automatic"
    ) -join " "
}

function Invoke-Go([string[]]$GoArgs, [string]$TargetOS = $GOOS, [string]$TargetArch = $GOARCH) {
    $oldGoCache = $env:GOCACHE
    $oldGoOS = $env:GOOS
    $oldGoArch = $env:GOARCH
    $oldCGO = $env:CGO_ENABLED
    try {
        $env:GOCACHE = $GoCache
        $env:GOOS = $TargetOS
        $env:GOARCH = $TargetArch
        $env:CGO_ENABLED = $CGOEnabled
        & $GO @GoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "go command failed: $($GoArgs -join ' ')"
        }
    } finally {
        $env:GOCACHE = $oldGoCache
        $env:GOOS = $oldGoOS
        $env:GOARCH = $oldGoArch
        $env:CGO_ENABLED = $oldCGO
    }
}

# 构建单个平台二进制。正式 release 会额外注入版本和精简 linker flags。
function Build-Binary([string]$TargetOS, [string]$TargetArch, [string]$Output) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Output) | Out-Null
    Write-Host "==> build $TargetOS/$TargetArch $Output"
    $goArgs = @("build", "-trimpath")
    if ($Tags) {
        $goArgs += @("-tags", $Tags)
    }
    if ($LdFlags) {
        $goArgs += @("-ldflags", $LdFlags)
    }
    $goArgs += @("-o", $Output, $Cmd)
    Invoke-Go $goArgs $TargetOS $TargetArch
}

function Binary-Path([string]$TargetOS, [string]$TargetArch, [string]$Root) {
    $output = Join-Path $Root $AppName
    if ($TargetOS -eq "windows") {
        $output = "$output.exe"
    }
    return $output
}

# 输出 Windows 命令帮助；参数名保持与 Makefile 和环境变量一致。
function Show-Help {
	@(
		"命令:",
		"  .\make.cmd dev                              以开发配置启动 Sparq",
		"  .\make.cmd run                              执行 ARGS 环境变量中的 Sparq CLI 命令",
		"  .\make.cmd build                            构建当前平台二进制到 bin\",
		"  .\make.cmd build -GOOS linux -GOARCH amd64 指定目标平台构建二进制",
		"  .\make.cmd build-all                        构建 PLATFORMS 中的全部平台",
		"  .\make.cmd release -Version x.y.z          构建未精简的多平台发布 zip 归档",
		"  .\make.cmd release-optimized -Version x.y.z 构建去调试信息的生产 zip 归档",
		"  .\make.cmd test                             执行 go test ./...",
		"  .\make.cmd fmt                              执行 gofmt",
		"  .\make.cmd tidy                             执行 go mod tidy",
		"  .\make.cmd clean                            删除 bin\ 和 dist\"
	) | ForEach-Object { Write-Host $_ }
}

switch ($Target) {
    "help" {
        Show-Help
    }
    "dev" {
        # 开发启动使用宿主平台和开发配置，不写入发布目录。
        $devArgs = @("run", $Cmd, "serve", "--config", $Config, "--env", $EnvName)
        Invoke-Go $devArgs $HostGOOS $HostGOARCH
    }
    "run" {
        # 将 ARGS 按空白拆分为 CLI 参数；复杂参数请直接使用 Go 或 PowerShell 命令行。
        $runArgs = @("run", $Cmd)
        if ($Args) {
            $runArgs += ($Args -split "\s+")
        }
        Invoke-Go $runArgs $HostGOOS $HostGOARCH
    }
    "build" {
        # 构建当前平台的本地二进制，不执行发布归档清理。
        $output = Binary-Path $GOOS $GOARCH $BinDir
        Build-Binary $GOOS $GOARCH $output
    }
    "build-all" {
        # 仅生成各平台二进制目录，不复制 config 或 public。
        foreach ($platform in ($Platforms -split "\s+")) {
            if (-not $platform) { continue }
            $parts = $platform -split "/"
            if ($parts.Length -ne 2) { throw "invalid platform: $platform" }
            $name = "$AppName`_$($parts[0])_$($parts[1])"
            $root = Join-Path $DistDir $name
            $output = Binary-Path $parts[0] $parts[1] $root
            Build-Binary $parts[0] $parts[1] $output
        }
    }
    "release" {
        # 每个平台分别生成目录和 zip；排除安装配置及运行期插件资源。
        foreach ($platform in ($Platforms -split "\s+")) {
            if (-not $platform) { continue }
            $parts = $platform -split "/"
            if ($parts.Length -ne 2) { throw "invalid platform: $platform" }
            $name = "$AppName`_$Version`_$($parts[0])_$($parts[1])"
            $root = Join-Path $DistDir $name
            if (Test-Path $root) { Remove-Item -Recurse -Force $root }
            New-Item -ItemType Directory -Force -Path $root | Out-Null
            $output = Binary-Path $parts[0] $parts[1] $root
            $originalLdFlags = $LdFlags
            $LdFlags = $ReleaseLdFlags
            try {
                Build-Binary $parts[0] $parts[1] $output
            } finally {
                $LdFlags = $originalLdFlags
            }
            Copy-Item -Recurse -Path "config" -Destination (Join-Path $root "config")
            $installConfig = Join-Path $root "config/app.install.yaml"
            if (Test-Path $installConfig) { Remove-Item -Force $installConfig }
            if (Test-Path "public") {
                Copy-Item -Recurse -Path "public" -Destination (Join-Path $root "public")
            }
            $pluginAssets = Join-Path $root "public/admin/plugin-assets"
            if (Test-Path $pluginAssets) { Remove-Item -Recurse -Force $pluginAssets }
            $archive = Join-Path $DistDir "$name.zip"
            if (Test-Path $archive) { Remove-Item -Force $archive }
            Compress-Archive -Path $root -DestinationPath $archive
        }
    }
    "release-optimized" {
        # 复用 release 的归档逻辑，只额外注入精简 linker flags 并关闭 CGO。
        $originalLdFlags = $LdFlags
        $LdFlags = ($LdFlags + " -s -w -buildid=").Trim()
        try {
            & $PSCommandPath -Target release -GO $GO -AppName $AppName -Cmd $Cmd -DistDir $DistDir -Version $Version -Platforms $Platforms -GoCache $GoCache -CGOEnabled "0" -Tags $Tags -LdFlags $LdFlags
            if ($LASTEXITCODE -ne 0) { throw "optimized release failed" }
        } finally {
            $LdFlags = $originalLdFlags
        }
    }
    "test" {
        # 使用宿主平台执行当前模块全部 Go 测试。
        Invoke-Go @("test", "./...") $HostGOOS $HostGOARCH
    }
    "fmt" {
        # 格式化当前模块全部 Go 文件。
        & gofmt -w .
        if ($LASTEXITCODE -ne 0) { throw "gofmt failed" }
    }
    "tidy" {
        # 整理当前模块 Go 依赖。
        & $GO mod tidy
        if ($LASTEXITCODE -ne 0) { throw "go mod tidy failed" }
    }
    "clean" {
        # 只删除脚本生成的 bin 和 dist 目录。
        if (Test-Path $BinDir) { Remove-Item -Recurse -Force $BinDir }
        if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
    }
    default {
        Show-Help
        throw "unknown target: $Target"
    }
}
