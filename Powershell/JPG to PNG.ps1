$SourceDir = "PATH\TO\FILES"
$OutDir    = "PATH\TO\FILES"

if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Get-ChildItem $SourceDir -Recurse -Include *.jpg,*.jpeg | ForEach-Object {
    $pngPath = Join-Path $OutDir ($_.BaseName + ".png")
    magick "$($_.FullName)" "$pngPath"
}
