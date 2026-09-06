param([string]$GamePath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cli=Join-Path $root 'tools\agent.ps1'
$bridge=Join-Path $root ('build\agent-qa-'+[Guid]::NewGuid().ToString('N'))
$script:checks=0
$script:failures=0
$script:launched=$false
$report=$null
function Check([bool]$Condition,[string]$Label) {
    $script:checks++
    if (-not $Condition) { $script:failures++; Write-Warning "FAIL: $Label" }
}
function Call([string]$Action,[hashtable]$Parameters=@{}) {
    return (& $cli $Action @Parameters -BridgeDir $bridge -AsObject)
}
function Raw($Request,[string]$RawText='') {
    $path=Join-Path $bridge ('requests\'+$Request.id+'.json')
    $utf8=[Text.UTF8Encoding]::new($false)
    $text=if ($RawText) {$RawText} else {ConvertTo-Json -InputObject $Request -Compress -Depth 10}
    [IO.File]::WriteAllText($path+'.tmp',$text,$utf8);[IO.File]::Move($path+'.tmp',$path)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while (Test-Path -LiteralPath $path) {
        if ($timer.Elapsed.TotalSeconds -gt 10) {throw 'Raw request was not consumed'}
        Start-Sleep -Milliseconds 40
    }
    return (Get-Content -LiteralPath (Join-Path $bridge ('responses\'+$Request.id+'.json')) -Raw | ConvertFrom-Json)
}
try {
    $launchArgs=@{Isolated=$true}
    if ($GamePath) {$launchArgs.GamePath=$GamePath}
    $started=Call 'launch' $launchArgs
    if (-not $started.ok) {throw ($started | ConvertTo-Json -Depth 4)}
    $script:launched=$true
    $state=Call 'status' @{Full=$true}
    Check ($state.ui.visible -and $state.ui.speed -eq 0) 'actual GUI launches paused'
    Check ($state.available_actions.Count -gt 0 -and $state.idle_workers -eq 2) 'live derived state and legal actions'
    $session=$state.session_id
    $id=[Guid]::NewGuid().ToString('N')
    $first=Call 'build' @{Room=5;Kind='lab';RequestId=$id}
    Check ($first.ok -and $first.state.simulation.stock.scrap -eq 180) 'build uses real cost'
    $duplicate=Call 'build' @{Room=5;Kind='lab';RequestId=$id}
    Check ($duplicate.ok -and $duplicate.state.simulation.stock.scrap -eq 180) 'CLI retry returns original response'
    $duplicate=Raw $first.request
    $fresh=Call 'status' @{Full=$true}
    Check ($duplicate.ok -and $fresh.simulation.stock.scrap -eq 180) 'server replay cannot spend twice'
    $bad=Call 'assign' @{Room=5;Delta=1}
    Check (-not $bad.ok -and $bad.code -eq 'rejected') 'unfinished room staffing rejected'
    $bad=Call 'assign' @{Room=0;Delta=2}
    Check (-not $bad.ok -and $bad.code -eq 'invalid_action') 'invalid delta rejected'
    $bad=Call 'state' @{ExpectedSequence=0}
    Check (-not $bad.ok -and $bad.code -eq 'stale_state') 'stale snapshot precondition rejected'
    $wrong=Raw @{id=[Guid]::NewGuid().ToString('N');session_id='old-session';action='fortify';args=@{}}
    Check ($wrong.code -eq 'wrong_session') 'old session cannot mutate game'
    $malformed=Raw @{id=[Guid]::NewGuid().ToString('N')} '{broken'
    Check ($malformed.code -eq 'invalid_request') 'malformed JSON has a bounded rejection'
    $result=Call 'step' @{Seconds=15}
    Check ($result.ok -and $result.state.simulation.rooms[5].build_left -eq 0) 'step completes live construction'
    $result=Call 'assign' @{Room=5;Delta=1}
    Check ($result.ok -and $result.state.simulation.rooms[5].workers -eq 1) 'JSON numeric assignment works'
    $result=Call 'tab' @{Name='Research'}
    Check ($result.ok -and $result.state.ui.tab -eq 'Research') 'CLI updates the visible GUI tab'
    $result=Call 'research' @{Key='efficiency'}
    Check ($result.ok) 'research action accepted'
    $result=Call 'step' @{Seconds=28}
    Check ($result.ok -and 'efficiency' -in $result.state.simulation.unlocked) 'research unlock reaches live state'
    $shot=Call 'screenshot'
    Check ($shot.ok -and (Test-Path -LiteralPath $shot.result.path)) 'real GUI screenshot is available'
    $result=Call 'save'
    Check ($result.ok -and (Test-Path -LiteralPath (Join-Path $bridge 'isolated_save.json'))) 'isolated save written'
    $savedElapsed=$result.state.simulation.elapsed
    $null=Call 'step' @{Seconds=4}
    $result=Call 'load'
    Check ($result.ok -and $result.state.simulation.elapsed -eq $savedElapsed -and $result.state.ui.speed -eq 0) 'CLI load restores and pauses'
    $result=Call 'speed' @{Rate=4}
    Check ($result.ok -and $result.state.ui.speed -eq 4) 'JSON numeric speed works'
    $bad=Call 'step' @{Seconds=1}
    Check (-not $bad.ok) 'real-time mode cannot also accept deterministic steps'
    $null=Call 'pause'

    # Play a complete fresh run through the public CLI, in this test-only save.
    $result=Call 'new_game' @{ConfirmReset=$true}
    Check ($result.ok -and $result.state.simulation.elapsed -eq 0) 'isolated campaign resets with explicit confirmation'
    $result=Call 'expedition' @{Route='depot'};Check ([bool]$result.ok) 'campaign dispatch'
    $result=Call 'build' @{Room=5;Kind='lab'};Check ([bool]$result.ok) 'campaign construction'
    $null=Call 'step' @{Seconds=30};$null=Call 'step' @{Seconds=3}
    $result=Call 'assign' @{Room=5;Delta=1};Check ([bool]$result.ok) 'campaign staffing'
    $result=Call 'research' @{Key='efficiency'};Check ([bool]$result.ok) 'campaign efficiency'
    $null=Call 'step' @{Seconds=28}
    $result=Call 'research' @{Key='relay'};Check ([bool]$result.ok) 'campaign relay'
    $state=$result.state
    for ($turn=0;$turn -lt 80 -and -not $state.simulation.outcome;$turn++) {
        if ($state.next_raid.in_seconds -le 21 -and -not $state.simulation.braced) {
            $result=Call 'fortify';if (-not $result.ok) {throw $result.error};$state=$result.state
        }
        if ($state.simulation.integrity -lt 75) {
            $result=Call 'repair';if (-not $result.ok) {throw $result.error};$state=$result.state
        }
        $result=Call 'step' @{Seconds=20}
        if (-not $result.ok) {throw $result.error}
        $state=$result.state
    }
    Check ($state.simulation.outcome -eq 'victory' -and $state.day -ge 7) 'agent wins through live GUI CLI actions'
    $result=Call 'screenshot'
    Check ($result.ok) 'victory GUI screenshot'
    $report=[ordered]@{checks=$script:checks;failures=$script:failures;bridge_dir=$bridge;session_id=$session;outcome=$state.simulation.outcome;day=$state.day;survivors=$state.simulation.survivors;integrity=$state.simulation.integrity;screenshot=$result.result.path}
    $report | ConvertTo-Json
} catch {
    $script:failures++;Write-Warning $_.Exception.Message
} finally {
    if ($script:launched) {$closed=Call 'shutdown';Check ([bool]$closed.ok) 'isolated test GUI shuts down after save'}
}
if ($report) {
    $report.checks=$script:checks;$report.failures=$script:failures
    $report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'build\agent-test-report.json')
}
Write-Output "AGENT_GUI_TESTS: $script:checks checks, $script:failures failures"
if ($script:failures) {exit 1}
