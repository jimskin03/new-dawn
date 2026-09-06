param(
    [string]$Godot = 'D:\Download\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Blender = 'D:\Program Files\Blender Foundation\Blender 5.2\blender.exe',
    [switch]$Render,
    [switch]$AgentGuiTest
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    New-Item -ItemType Directory -Force -Path 'build\Windows' | Out-Null
    if ($Render) {
        & $Blender --background --python-exit-code 1 --python 'art\build_assets.py'
        if ($LASTEXITCODE -ne 0) { throw 'Blender rendering failed.' }
    }
    & $Godot --headless --path $projectRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $Godot --headless --path $projectRoot --script 'tests\test_simulation.gd'
    if ($LASTEXITCODE -ne 0) { throw 'Simulation tests failed.' }
    & $Godot --headless --path $projectRoot --script 'tests\test_agent_bridge.gd'
    if ($LASTEXITCODE -ne 0) { throw 'Agent bridge tests failed.' }
    & $Godot --headless --path $projectRoot -- --smoke
    if ($LASTEXITCODE -ne 0) { throw 'Input and UI tests failed.' }
    & $Godot --headless --path $projectRoot -- --save-smoke
    if ($LASTEXITCODE -ne 0) { throw 'Save tests failed.' }
    & $Godot --headless --path $projectRoot --script 'tools\write_notices.gd'
    & $Godot --headless --path $projectRoot --export-pack 'Windows Desktop' 'build/Windows/NewDawn.pck'
    if ($LASTEXITCODE -ne 0) { throw 'Game pack export failed.' }
    # The installed runtime can run a PCK without downloadable export templates.
    $runtimePath = $Godot -replace '_console\.exe$', '.exe'
    Copy-Item -LiteralPath $runtimePath -Destination 'build\Windows\NewDawn.exe' -Force
    Copy-Item -LiteralPath 'docs\third_party\Godot.txt','docs\third_party\Inter-OFL.txt' -Destination 'build\Windows' -Force
    Copy-Item -LiteralPath 'docs\PLAY.txt' -Destination 'build\Windows\READ_ME.txt' -Force
    New-Item -ItemType Directory -Force -Path 'build\Windows\tools','build\Windows\docs' | Out-Null
    Copy-Item -LiteralPath 'tools\agent.ps1' -Destination 'build\Windows\tools\agent.ps1' -Force
    Copy-Item -LiteralPath 'docs\AGENT_PLAY.md' -Destination 'build\Windows\docs\AGENT_PLAY.md' -Force
    Copy-Item -LiteralPath 'Agent Play.cmd','AGENTS.md' -Destination 'build\Windows' -Force
    if ($AgentGuiTest) {
        & '.\tests\test_agent_cli.ps1'
        if ($LASTEXITCODE -ne 0) { throw 'Agent GUI integration tests failed.' }
    }
    Write-Output 'Ready: build\Windows\NewDawn.exe'
} finally { Pop-Location }
