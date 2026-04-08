# =======================
# MULTI-SOURCE FILE MOVER
# =======================

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName Microsoft.VisualBasic

$SourceRoots = @(
    "PATH\TO\FILE"
)

$Destination = "PATH\TO\FILE"
$LogFile = Join-Path $Destination "move_failures.log"

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

"" | Out-File -LiteralPath $LogFile -Force

foreach ($SourceRoot in $SourceRoots) {
    if (-not (Test-Path -LiteralPath $SourceRoot)) { continue }

    # UNZIP ALL ZIP FILES
    $ZipFiles = Get-ChildItem -LiteralPath $SourceRoot -Recurse -Filter *.zip -File -Force -ErrorAction SilentlyContinue

    foreach ($Zip in $ZipFiles) {
        try {
            $ExtractPath = $Zip.DirectoryName

            Expand-Archive -LiteralPath $Zip.FullName -DestinationPath $ExtractPath -Force

            $ExtractedFiles = Get-ChildItem -LiteralPath $ExtractPath -File -Force -ErrorAction SilentlyContinue |
                              Where-Object { $_.LastWriteTime -ge $Zip.LastWriteTime.AddSeconds(-5) }

            foreach ($File in $ExtractedFiles) {
                $TargetPath = Join-Path $ExtractPath $File.Name
                $BaseName = $File.BaseName
                $Extension = $File.Extension
                $Counter = 1

                while (Test-Path -LiteralPath $TargetPath) {
                    $TargetPath = Join-Path $ExtractPath "$BaseName ($Counter)$Extension"
                    $Counter++
                }

                if ($TargetPath -ne $File.FullName) {
                    Move-Item -LiteralPath $File.FullName -Destination $TargetPath -Force
                }
            }

            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Zip.FullName,
                'OnlyErrorDialogs',
                'SendToRecycleBin'
            )
        }
        catch {
            $Zip.FullName | Out-File -LiteralPath $LogFile -Append
        }
    }

    # MOVE ALL FILES
    $Files = Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -ne ".zip" }

    foreach ($File in $Files) {
        try {
            $BaseName = $File.BaseName
            $Extension = $File.Extension
            $TargetPath = Join-Path $Destination $File.Name
            $Counter = 1

            while (Test-Path -LiteralPath $TargetPath) {
                $TargetPath = Join-Path $Destination "$BaseName ($Counter)$Extension"
                $Counter++
            }

            Move-Item -LiteralPath $File.FullName -Destination $TargetPath -Force
        }
        catch {
            $File.FullName | Out-File -LiteralPath $LogFile -Append
        }
    }
}

Read-Host "Press Enter to exit"
