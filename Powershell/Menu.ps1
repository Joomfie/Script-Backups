# ToolMenu.ps1
# Self-elevate if not running as Administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# ─────────────────────────────────────────────
# FUNCTIONS
# ─────────────────────────────────────────────

function Kill-COMSurrogate {
    Write-Host ""
    Write-Host "Killing COM Surrogate (dllhost)..." -ForegroundColor Cyan
    Get-Process dllhost -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "Done." -ForegroundColor Green
}

function Restart-ExplorerAndSFC {
    Write-Host ""
    Write-Host "Restarting Windows Explorer..." -ForegroundColor Cyan
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Host "Explorer restarted." -ForegroundColor Green
    Start-Sleep -Seconds 5

    Write-Host "Running System File Checker (sfc /scannow)..." -ForegroundColor Cyan
    Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow
    Write-Host "SFC scan completed." -ForegroundColor Green
}

function Kill-CompactGUI {
    Write-Host ""
    $processName = "CompactGUI"
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name $processName -Force
        Write-Host "CompactGUI has been force closed." -ForegroundColor Green
    } else {
        Write-Host "CompactGUI is not currently running." -ForegroundColor Yellow
    }
}

function Clean-MedalClips {
    Write-Host ""
    Add-Type -AssemblyName Microsoft.VisualBasic

    $folders = @(
        "D:\Medal\Clips",
        "D:\Medal\Screenshots",
        "D:\Medal\Thumbnails",
        "D:\Medal\Video-Editor"
    )

    foreach ($folder in $folders) {
        if (Test-Path $folder) {
            Write-Host "Cleaning $folder..." -ForegroundColor Cyan

            Get-ChildItem -Path $folder -Recurse -Force -File | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Host "  Deleted file: $($_.Name)"
                } catch {
                    Write-Host "  Skipped (in use): $($_.Name)" -ForegroundColor Yellow
                }
            }

            Get-ChildItem -Path $folder -Recurse -Force -Directory |
                Sort-Object -Property FullName -Descending |
                ForEach-Object {
                    try {
                        Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
                        Write-Host "  Deleted folder: $($_.Name)"
                    } catch {
                        Write-Host "  Skipped folder (in use): $($_.Name)" -ForegroundColor Yellow
                    }
                }

            Write-Host "Done: $folder" -ForegroundColor Green
        } else {
            Write-Host "Folder not found, skipping: $folder" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "Clearing Recycle Bin..." -ForegroundColor Cyan
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0xA)
        $recycleBin.Items() | ForEach-Object {
            Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Recycle Bin emptied." -ForegroundColor Green
    } catch {
        Write-Host "Could not empty Recycle Bin: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "All done! Medal folders cleaned and Recycle Bin emptied." -ForegroundColor Green
}

function Start-ASF {
    Write-Host ""
    Write-Host "Starting ArchiSteamFarm (without admin)..." -ForegroundColor Cyan
    $asfPath = "PATH/TO/FILE"
    $taskName = "RunASFAsUser"
    $action = New-ScheduledTaskAction -Execute $asfPath
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "ArchiSteamFarm launched." -ForegroundColor Green
}

# ─────────────────────────────────────────────
# MENU LOOP
# ─────────────────────────────────────────────

do {
    Clear-Host
    Write-Host "===============================" -ForegroundColor DarkCyan
    Write-Host "        TOOL MENU              " -ForegroundColor White
    Write-Host "===============================" -ForegroundColor DarkCyan
    Write-Host " 1. Kill COM Surrogate"
    Write-Host " 2. Restart Explorer + SFC Scan"
    Write-Host " 3. Kill CompactGUI"
    Write-Host " 4. Clean Medal Clips"
    Write-Host " 5. Start ArchiSteamFarm"
    Write-Host " 6. Exit"
    Write-Host "===============================" -ForegroundColor DarkCyan
    Write-Host ""
    $choice = Read-Host "Select an option (1-6)"

    switch ($choice) {
        "1" { Kill-COMSurrogate }
        "2" { Restart-ExplorerAndSFC }
        "3" { Kill-CompactGUI }
        "4" { Clean-MedalClips }
        "5" { Start-ASF }
        "6" { Write-Host "Goodbye." -ForegroundColor DarkGray; exit }
        default { Write-Host "Invalid option. Please enter 1-6." -ForegroundColor Red }
    }

    if ($choice -ne "6") {
        Write-Host ""
        Write-Host "Press any key to return to the menu..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }

} while ($true)
