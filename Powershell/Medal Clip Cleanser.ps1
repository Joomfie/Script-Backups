Add-Type -AssemblyName Microsoft.VisualBasic

$folders = @(
    "D:\Medal\Clips",
    "D:\Medal\Screenshots",
    "D:\Medal\Thumbnails",
    "D:\Medal\Video-Editor"
)

foreach ($folder in $folders) {
    if (Test-Path $folder) {
        Write-Host "Cleaning $folder..."

        # Delete all files directly in folder and subfolders
        Get-ChildItem -Path $folder -Recurse -Force -File | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                Write-Host "  Deleted file: $($_.Name)"
            } catch {
                Write-Host "  Skipped (in use): $($_.Name)"
            }
        }

        # Delete all subfolders after files are removed
        Get-ChildItem -Path $folder -Recurse -Force -Directory |
            Sort-Object -Property FullName -Descending |
            ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
                    Write-Host "  Deleted folder: $($_.Name)"
                } catch {
                    Write-Host "  Skipped folder (in use): $($_.Name)"
                }
            }

        Write-Host "Done: $folder"
    } else {
        Write-Host "Folder not found, skipping: $folder"
    }
}

Write-Host ""
Write-Host "Clearing Recycle Bin..."

# Empty Recycle Bin
try {
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.NameSpace(0xA)
    $recycleBin.Items() | ForEach-Object {
        Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Recycle Bin emptied."
} catch {
    Write-Host "Could not empty Recycle Bin: $_"
}

Write-Host ""
Write-Host "All done! Medal folders cleaned and Recycle Bin emptied."
Start-Sleep -Seconds 2
