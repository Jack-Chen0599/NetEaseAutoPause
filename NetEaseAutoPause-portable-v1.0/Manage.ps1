param([ValidateSet('Install','Start','Stop','Check','Uninstall')][string]$Action='Install')
$ErrorActionPreference='Stop'
$installDir=Join-Path $env:LOCALAPPDATA 'Programs\NetEaseAutoPause'
$exe=Join-Path $installDir 'NetEaseAutoPause.exe'
$startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'NetEaseAutoPause.lnk'
$marker=Join-Path $installDir '.netease-autopause-package'
function Stop-App {
    if (-not (Test-Path -LiteralPath $installDir)) { return }
    New-Item -ItemType File -Force (Join-Path $installDir 'stop.request') | Out-Null
    $ours=@(Get-CimInstance Win32_Process | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath -ieq $exe) -or
        ($_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $installDir 'watcher.py'),[StringComparison]::OrdinalIgnoreCase) -ge 0)
    })
    foreach ($item in $ours) {
        $proc=Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if ($proc -and -not $proc.WaitForExit(15000)) { throw 'App did not stop. Close it before trying again.' }
    }
}
function Check-App {
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Run Install.cmd first.' }
    $p=Start-Process -FilePath $exe -ArgumentList '--check' -WindowStyle Hidden -PassThru -Wait
    $report=Join-Path $installDir 'diagnostics.json'
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $report)) { throw "Check failed. See $installDir" }
    Get-Content -LiteralPath $report
}
function Start-App {
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Run Install.cmd first.' }
    Start-Process -FilePath $exe -WorkingDirectory $installDir -WindowStyle Hidden
    $deadline=(Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 300
        $pidFile=Join-Path $installDir 'running.pid'
        if (Test-Path -LiteralPath $pidFile) {
            $watcherPid=0
            if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(),[ref]$watcherPid)) {
                $p=Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
                if ($p -and $p.Path -ieq $exe) { Write-Host 'Running in background.'; return }
            }
        }
    } while ((Get-Date) -lt $deadline)
    throw "Startup failed. See startup-error.log or activity.log in $installDir"
}
switch ($Action) {
    'Install' {
        if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows 10/11 x64 is required.' }
        $source=Join-Path $PSScriptRoot 'app\NetEaseAutoPause'
        if (-not (Test-Path -LiteralPath (Join-Path $source 'NetEaseAutoPause.exe'))) { throw 'Extract the entire ZIP before installation.' }
        Stop-App
        New-Item -ItemType Directory -Force $installDir | Out-Null
        Get-ChildItem -LiteralPath $source | Copy-Item -Destination $installDir -Recurse -Force
        Set-Content -LiteralPath $marker -Value 'NetEaseAutoPause-v1' -Encoding ASCII
        Copy-Item (Join-Path $PSScriptRoot 'Manage.ps1'),(Join-Path $PSScriptRoot 'README-中文.md') -Destination $installDir -Force
        foreach ($name in @('Start.cmd','Stop.cmd','Check.cmd','Uninstall.cmd')) { Copy-Item (Join-Path $PSScriptRoot $name) -Destination $installDir -Force }
        Check-App
        $shell=New-Object -ComObject WScript.Shell
        $link=$shell.CreateShortcut($startup)
        $link.TargetPath=$exe;$link.WorkingDirectory=$installDir;$link.WindowStyle=7
        $link.Description='NetEase music auto-pause, no popup';$link.Save()
        $vbs=@('Set shell = CreateObject("WScript.Shell")','base = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)','shell.Run Chr(34) & base & "\NetEaseAutoPause.exe" & Chr(34), 0, False')
        $vbs | Set-Content (Join-Path $installDir 'Start.vbs') -Encoding ASCII
        Start-App
        Write-Host "Installed for current user: $installDir"
        Write-Host 'Autostart enabled. Enable Ctrl+Alt+P global play/pause in NetEase.'
    }
    'Start' { Start-App }
    'Stop' { Stop-App; Write-Host 'Stopped for now. Autostart remains enabled.' }
    'Check' { Check-App }
    'Uninstall' {
        if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'NetEaseAutoPause-v1') { throw 'Installation marker missing; refusing to delete an unverified directory.' }
        $resolved=(Resolve-Path -LiteralPath $installDir).Path
        $expected=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\NetEaseAutoPause'))
        if ($resolved -ine $expected -or (Get-Item -LiteralPath $resolved).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw 'Unexpected uninstall path.' }
        Stop-App
        if (Test-Path -LiteralPath $startup) {
            $link=(New-Object -ComObject WScript.Shell).CreateShortcut($startup)
            if ($link.TargetPath -ieq $exe -or $link.TargetPath -ieq (Join-Path $installDir '.venv\Scripts\pythonw.exe')) { Remove-Item -LiteralPath $startup }
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Write-Host 'Uninstalled. NetEase Cloud Music itself was not changed.'
    }
}
