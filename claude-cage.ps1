<#
.SYNOPSIS
    Start claude-cage on Windows with one command.

.DESCRIPTION
    Runs claude-cage.sh inside WSL.  Without arguments it starts Docker
    Desktop when needed, brings the container up (the first run builds the
    image) and opens Claude Desktop.  Any arguments are passed unchanged to
    claude-cage.sh, for example `chromium`, `down` or `run curl ...`.

    The repository is located in this order:
      1. CLAUDE_CAGE_DISTRO and CLAUDE_CAGE_PATH environment variables;
      2. the script's own location when it is started from
         \\wsl.localhost\<distro>\... or \\wsl$\<distro>\...;
      3. ~/claude-cage in the default WSL distribution.

    `shortcut` as the only argument creates a desktop shortcut instead.
    `menu-install <icon dir> <apps...>` and `menu-remove` manage the Start
    menu folder "claude-cage"; claude-cage.sh calls them through WSL interop
    after `up`.

.EXAMPLE
    .\claude-cage.ps1
.EXAMPLE
    .\claude-cage.ps1 chromium
.EXAMPLE
    .\claude-cage.ps1 shortcut
#>

# NOTE: No param() block on purpose: every argument, including ones that
# start with '-', must reach claude-cage.sh untouched.
# NOTE: Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less
# scripts in the ANSI code page.
Set-StrictMode -Version 2.0

$DockerTimeoutSeconds = 180
$MenuNames = @{
    claude = 'Claude (cage)'
    firefox = 'Firefox (cage)'
    chromium = 'Chromium (cage)'
}

function Fail([string]$Message) {
    Write-Host "claude-cage: $Message" -ForegroundColor Red
    exit 1
}

function Get-WslPrefix([string]$Distro) {
    if ($Distro) {
        return @('-d', $Distro)
    }
    return @()
}

function Resolve-Repository {
    $distro = $Env:CLAUDE_CAGE_DISTRO
    $path = $Env:CLAUDE_CAGE_PATH
    if (-not $distro -and -not $path -and
            $PSScriptRoot -match '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)(\\.*)?$') {
        $distro = $Matches[1]
        $path = ($Matches[2] -replace '\\', '/')
    }
    if (-not $path) {
        $prefix = Get-WslPrefix $distro
        $output = @(& wsl.exe @prefix --exec printenv HOME)
        if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0 -or -not $output[0]) {
            Fail "failed to read HOME from WSL; is a WSL 2 distribution installed?"
        }
        $path = "$($output[0].Trim())/claude-cage"
    }
    return @{ Distro = $distro; Path = $path }
}

function Test-Docker([string[]]$Prefix) {
    & wsl.exe @Prefix --exec docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

function Start-Docker([string[]]$Prefix) {
    if (Test-Docker $Prefix) {
        return
    }
    $exe = Join-Path $Env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Fail "Docker Desktop is not running and '$exe' does not exist"
    }
    Write-Host "claude-cage: starting Docker Desktop..."
    Start-Process -FilePath $exe
    $deadline = (Get-Date).AddSeconds($DockerTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-Docker $Prefix) {
            return
        }
    }
    Fail ("Docker is not reachable from WSL after $DockerTimeoutSeconds s; check " +
        "Settings -> Resources -> WSL integration in Docker Desktop")
}

function New-Shortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $file = Join-Path $desktop 'Claude (cage).lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($file)
    # NOTE: The .cmd launcher keeps the window open when something fails.
    $link.TargetPath = Join-Path $PSScriptRoot 'claude-cage.cmd'
    $link.WorkingDirectory = $desktop
    $link.Description = 'Start claude-cage and open Claude Desktop'
    $link.Save()
    Write-Host "claude-cage: created $file"
}

# Wrap a PNG into a single-image .ico file (Windows Vista and later read PNG
# data inside .ico).  Width and height come from the PNG header; 0 means 256.
function ConvertTo-Icon([string]$Png, [string]$Ico) {
    $data = [IO.File]::ReadAllBytes($Png)
    $width = ([int]$data[16] -shl 24) -bor ([int]$data[17] -shl 16) -bor ([int]$data[18] -shl 8) -bor [int]$data[19]
    $height = ([int]$data[20] -shl 24) -bor ([int]$data[21] -shl 16) -bor ([int]$data[22] -shl 8) -bor [int]$data[23]
    if ($width -gt 256 -or $height -gt 256) {
        # NOTE: An .ico image is at most 256 x 256; scale larger PNGs down.
        # Without System.Drawing the original PNG is kept as it is.  Types are
        # looked up by name, so the function still loads where it is missing.
        try {
            Add-Type -AssemblyName System.Drawing
            $pngStream = New-Object IO.MemoryStream(, $data)
            $source = ('System.Drawing.Image' -as [type])::FromStream($pngStream)
            $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList 256, 256
            $graphics = ('System.Drawing.Graphics' -as [type])::FromImage($bitmap)
            $graphics.InterpolationMode = 'HighQualityBicubic'
            $graphics.DrawImage($source, 0, 0, 256, 256)
            $output = New-Object IO.MemoryStream
            $bitmap.Save($output, ('System.Drawing.Imaging.ImageFormat' -as [type])::Png)
            $data = $output.ToArray()
            $width = 256
            $height = 256
            $graphics.Dispose()
            $bitmap.Dispose()
            $source.Dispose()
        } catch {
            Write-Host "claude-cage: kept '$Png' at ${width}x${height}: $($_.Exception.Message)"
        }
    }
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]1)
    $writer.Write([byte]$(if ($width -ge 256) { 0 } else { $width }))
    $writer.Write([byte]$(if ($height -ge 256) { 0 } else { $height }))
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$data.Length)
    $writer.Write([UInt32]22)
    $writer.Write($data)
    $writer.Flush()
    [IO.File]::WriteAllBytes($Ico, $stream.ToArray())
    $writer.Dispose()
}

function Get-MenuFolder {
    return Join-Path ([Environment]::GetFolderPath('Programs')) 'claude-cage'
}

function Get-IconFolder {
    return Join-Path $Env:LOCALAPPDATA 'claude-cage\icons'
}

# Start menu entries for container applications.  Each shortcut runs the
# .cmd launcher with `open <app>`, which starts Docker Desktop and the
# container when needed; the console window starts minimized.
function Install-Menu([string]$IconSource, [string[]]$Apps) {
    $menu = Get-MenuFolder
    $icons = Get-IconFolder
    New-Item -ItemType Directory -Force -Path $menu, $icons | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    foreach ($app in $Apps) {
        if (-not $MenuNames.ContainsKey($app)) {
            continue
        }
        $link = $shell.CreateShortcut((Join-Path $menu "$($MenuNames[$app]).lnk"))
        $link.TargetPath = Join-Path $PSScriptRoot 'claude-cage.cmd'
        $link.Arguments = "open $app"
        $link.WorkingDirectory = [Environment]::GetFolderPath('UserProfile')
        $link.WindowStyle = 7
        $link.Description = "$($MenuNames[$app]) from the claude-cage container"
        $png = Join-Path $IconSource "$app.png"
        if (Test-Path -LiteralPath $png) {
            $ico = Join-Path $icons "$app.ico"
            ConvertTo-Icon $png $ico
            $link.IconLocation = "$ico,0"
        }
        $link.Save()
    }
    Write-Host "claude-cage: Start menu entries installed in $menu"
}

function Remove-Menu {
    foreach ($path in @((Get-MenuFolder), (Split-Path (Get-IconFolder) -Parent))) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
    Write-Host "claude-cage: Start menu entries removed"
}

$cageArgs = @($args | ForEach-Object { [string]$_ })
if ($cageArgs.Count -ge 2 -and $cageArgs[0] -eq 'menu-install') {
    Install-Menu $cageArgs[1] @($cageArgs | Select-Object -Skip 2)
    exit 0
}
if ($cageArgs.Count -eq 1 -and $cageArgs[0] -eq 'menu-remove') {
    Remove-Menu
    exit 0
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe not found; install WSL with: wsl --install -d Ubuntu"
}
if ($cageArgs.Count -eq 1 -and $cageArgs[0] -eq 'shortcut') {
    New-Shortcut
    exit 0
}
$repo = Resolve-Repository
$prefix = Get-WslPrefix $repo.Distro
& wsl.exe @prefix --exec test -f "$($repo.Path)/claude-cage.sh"
if ($LASTEXITCODE -ne 0) {
    Fail ("claude-cage.sh not found in '$($repo.Path)'; clone the repository there " +
        "or set CLAUDE_CAGE_DISTRO and CLAUDE_CAGE_PATH")
}
Start-Docker $prefix
# NOTE: wsl.exe runs at script level, not inside a function, so it keeps the
# console (and its TTY for `shell`) instead of having its output captured.
if ($cageArgs.Count -ne 0) {
    & wsl.exe @prefix --cd $repo.Path --exec bash ./claude-cage.sh @cageArgs
    exit $LASTEXITCODE
}
& wsl.exe @prefix --cd $repo.Path --exec bash ./claude-cage.sh up
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& wsl.exe @prefix --cd $repo.Path --exec bash ./claude-cage.sh claude
exit $LASTEXITCODE
