<# Local CLI for the live New Dawn GUI. Run "agent.ps1 help" for examples. #>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'status',
    [string]$BridgeDir,
    [string]$GamePath,
    [int]$Room = -1,
    [string]$Kind,
    [int]$Delta = 0,
    [string]$Route,
    [string]$Key,
    [double]$Seconds = 1,
    [int]$Rate = 1,
    [string]$Name,
    [int]$Depth = 0,
    [string]$RequestId,
    [long]$ExpectedSequence = -1,
    [int]$TimeoutSeconds = 10,
    [int]$Count = 10,
    [switch]$Full,
    [switch]$AsObject,
    [switch]$Isolated,
    [switch]$ConfirmReset
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GamePath) {
    $GamePath = if (Test-Path -LiteralPath (Join-Path $projectRoot 'NewDawn.exe')) { Join-Path $projectRoot 'NewDawn.exe' } else { Join-Path $projectRoot 'build\Windows\NewDawn.exe' }
}
$GamePath = [IO.Path]::GetFullPath($GamePath)
if (-not $BridgeDir) { $BridgeDir = Join-Path (Split-Path -Parent $GamePath) '.agent' }
$BridgeDir = [IO.Path]::GetFullPath($BridgeDir)
$utf8 = [Text.UTF8Encoding]::new($false)

function Emit($Value) {
    if ($AsObject) { Write-Output $Value } else { ConvertTo-Json -InputObject $Value -Depth 50 }
}
function Read-JsonFile([string]$Path) {
    for ($attempt=0; $attempt -lt 5; $attempt++) {
        try { return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json) }
        catch { if ($attempt -eq 4) { throw }; Start-Sleep -Milliseconds 40 }
    }
}
function Read-LiveState {
    $value = Read-JsonFile (Join-Path $BridgeDir 'state.json')
    if ($value.protocol -ne 'new-dawn-agent/1') { throw 'Unexpected bridge protocol.' }
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$value.updated_at_ms
    if (-not $value.running -or $age -gt 5000) { throw 'The game is stopped or the live state is stale. Launch the GUI before issuing commands.' }
    return $value
}
function Compact-State($State) {
    return [ordered]@{
        protocol=$State.protocol; session_id=$State.session_id; pid=$State.pid
        sequence=$State.sequence; updated_at_ms=$State.updated_at_ms
        day=$State.day; elapsed=$State.simulation.elapsed; stock=$State.simulation.stock; rates=$State.rates
        survivors=$State.simulation.survivors; capacity=$State.capacity; idle_workers=$State.idle_workers
        integrity=$State.simulation.integrity; morale=$State.simulation.morale
        raid=$State.next_raid; braced=$State.simulation.braced; objective=$State.objective
        outcome=$State.simulation.outcome; expedition=$State.simulation.expedition
        research=$State.simulation.research; unlocked=$State.simulation.unlocked; ui=$State.ui
        rooms=@($State.simulation.rooms | Select-Object id,name,level,workers,build_left)
    }
}
function Same-Args($Actual, $Expected) {
    # JSON numbers return as doubles from Godot, even when the client sent integers.
    if (@($Actual.PSObject.Properties).Count -ne $Expected.Count) { return $false }
    foreach ($k in $Expected.Keys) {
        $property = $Actual.PSObject.Properties[$k]
        if ($null -eq $property) { return $false }
        $a=$property.Value; $b=$Expected[$k]
        if (($a -is [string]) -ne ($b -is [string]) -or ($a -is [bool]) -ne ($b -is [bool])) { return $false }
        if ($a -cne $b) { return $false }
    }
    return $true
}
function Send-Request([string]$Action, $Arguments) {
    $current = Read-LiveState
    $rpcId = if ($RequestId) { $RequestId } else { [Guid]::NewGuid().ToString('N') }
    if ($rpcId -notmatch '^[A-Za-z0-9_-]{1,80}$') { throw 'RequestId must contain 1-80 letters, digits, underscores, or hyphens.' }
    $request = [ordered]@{ id=$rpcId; session_id=$current.session_id; action=$Action; args=$Arguments }
    if ($ExpectedSequence -ge 0) { $request.expected_sequence = $ExpectedSequence }
    $responsePath = Join-Path $BridgeDir "responses\$rpcId.json"
    if (-not (Test-Path -LiteralPath $responsePath)) {
        $requestPath = Join-Path $BridgeDir "requests\$rpcId.json"
        $tempPath = "$requestPath.$([Guid]::NewGuid().ToString('N')).tmp"
        [IO.File]::WriteAllText($tempPath, (ConvertTo-Json -InputObject $request -Depth 12 -Compress), $utf8)
        # Publish only a complete command. The id remains stable if delivery is retried.
        if (Test-Path -LiteralPath $requestPath) {
            $pending = Read-JsonFile $requestPath
            if ($pending.session_id -ne $request.session_id -or $pending.action -ne $Action -or -not (Same-Args $pending.args $Arguments)) {
                [IO.File]::Delete($tempPath); throw 'RequestId is already used for a different command.'
            }
            [IO.File]::Delete($tempPath)
        } else { [IO.File]::Move($tempPath,$requestPath) }
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $responsePath)) {
        if ($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            throw "No response yet. The action outcome is unknown. Retry the SAME command with -RequestId $rpcId; do not create a new id."
        }
        Start-Sleep -Milliseconds 50
    }
    $response = Read-JsonFile $responsePath
    if ($response.session_id -ne $request.session_id -or $response.request.action -ne $Action -or -not (Same-Args $response.request.args $Arguments)) {
        throw 'RequestId belongs to another session or command. Do not reuse it.'
    }
    return $response
}

try {
    if ($Command -eq 'help') {
        Write-Output @'
New Dawn live GUI CLI (PowerShell 5.1+; no network or Python required)

  .\tools\agent.ps1 launch              Open or attach to the GUI, initially paused
  .\tools\agent.ps1 status              Compact live JSON state
  .\tools\agent.ps1 status -Full        Full state and all currently legal game actions
  .\tools\agent.ps1 actions             Currently legal actions, args and costs
  .\tools\agent.ps1 watch -Count 10     Ten state snapshots, one per second
  .\tools\agent.ps1 pause
  .\tools\agent.ps1 dismiss
  .\tools\agent.ps1 build -Room 5 -Kind lab
  .\tools\agent.ps1 step -Seconds 15    Advance up to 30 game seconds while paused
  .\tools\agent.ps1 assign -Room 5 -Delta 1
  .\tools\agent.ps1 research -Key efficiency
  .\tools\agent.ps1 expedition -Route depot
  .\tools\agent.ps1 upgrade -Room 1
  .\tools\agent.ps1 fortify
  .\tools\agent.ps1 repair
  .\tools\agent.ps1 resume
  .\tools\agent.ps1 speed -Rate 4
  .\tools\agent.ps1 select -Room 5
  .\tools\agent.ps1 tab -Name Research
  .\tools\agent.ps1 depth -Depth 2
  .\tools\agent.ps1 screenshot
  .\tools\agent.ps1 save
  .\tools\agent.ps1 load               Loads and pauses the game
  .\tools\agent.ps1 new_game -ConfirmReset
  .\tools\agent.ps1 shutdown           Save and close the game

Room IDs are ZERO-BASED: 0-9. Room 5 is GUI chamber 06.
Use -BridgeDir to target a different instance. Use launch -Isolated with a unique
-BridgeDir to keep a separate save there. Never use --headless for actual agent play.
Actions return JSON including ok/code/error and the resulting live state.
-AsObject returns a PowerShell object. -RequestId supports safe retries.
See docs/AGENT_PLAY.md for strategy and the language-independent JSON protocol.
'@
        return
    }
    if ($Command -eq 'launch') {
        $existing = $null
        try { $existing = Read-LiveState } catch { }
        if ($existing) {
            Emit ([ordered]@{ok=$true; attached=$true; bridge_dir=$BridgeDir; state=(Compact-State $existing)}); return
        }
        if (-not (Test-Path -LiteralPath $GamePath)) { throw "Game executable not found: $GamePath" }
        New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
        # Windows paths cannot contain a literal quote. Explicit quoting preserves spaces.
        $launchArguments = '--log-file "' + (Join-Path $BridgeDir 'game.log') + '" -- --agent-dir "' + $BridgeDir + '" --agent-paused'
        if ($Isolated) { $launchArguments += ' --save-path "' + (Join-Path $BridgeDir 'isolated_save.json') + '"' }
        $started = Start-Process -FilePath $GamePath -WorkingDirectory (Split-Path -Parent $GamePath) -ArgumentList $launchArguments -WindowStyle Normal -PassThru
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $fresh=$null
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            try { $candidate = Read-LiveState; if ([int]$candidate.pid -eq $started.Id) { $fresh=$candidate; break } } catch { }
            if ($started.HasExited) { throw "Game exited before the bridge became ready. See $BridgeDir\game.log" }
            Start-Sleep -Milliseconds 100
        }
        if (-not $fresh) { throw "Game started but its bridge was not ready in time. See $BridgeDir\game.log" }
        Emit ([ordered]@{ok=$true; attached=$false; bridge_dir=$BridgeDir; state=(Compact-State $fresh)}); return
    }
    if ($Command -in @('status','actions','watch')) {
        $iterations = if ($Command -eq 'watch') { [Math]::Max(1,$Count) } else { 1 }
        for ($i=0; $i -lt $iterations; $i++) {
            $state=Read-LiveState
            if ($Command -eq 'actions') { Emit @($state.available_actions) }
            elseif ($Full) { Emit $state } else { Emit (Compact-State $state) }
            if ($i -lt $iterations-1) { Start-Sleep -Seconds 1 }
        }
        return
    }
    $arguments = [ordered]@{}
    switch ($Command) {
        'build' { $arguments.room=$Room; $arguments.kind=$Kind }
        'assign' { $arguments.room=$Room; $arguments.delta=$Delta }
        'upgrade' { $arguments.room=$Room }
        'expedition' { $arguments.route=$Route }
        'research' { $arguments.key=$Key }
        'speed' { $arguments.rate=$Rate }
        'step' { $arguments.seconds=$Seconds }
        'select' { $arguments.room=$Room }
        'tab' { $arguments.name=$Name }
        'depth' { $arguments.value=$Depth }
        'new_game' { $arguments.confirm=[bool]$ConfirmReset }
    }
    $reply = Send-Request $Command $arguments
    Emit $reply
    if (-not $reply.ok) { exit 1 }
} catch {
    Emit ([ordered]@{ok=$false; code='client_error'; error=$_.Exception.Message; bridge_dir=$BridgeDir})
    exit 1
}
