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

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe not found; install WSL with: wsl --install -d Ubuntu"
}
$cageArgs = @($args | ForEach-Object { [string]$_ })
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
