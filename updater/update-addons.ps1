# Updates our addons in your WoW AddOns folder to the latest version on GitHub.
#
# Run it by double-clicking "Update WoW Addons.bat". The first time, it asks
# where your AddOns folder is and remembers the answer. After that it just
# downloads the newest addons and replaces the old folders. Your saved stats
# live in WoW's WTF folder, so they are never touched.
#
# Options (from a PowerShell prompt):
#   .\update-addons.ps1 -AddOnsPath "D:\Games\World of Warcraft\_classic_\Interface\AddOns"
#   .\update-addons.ps1 -ChangeFolder     # forget the saved folder and ask again

param(
  [string]$AddOnsPath,
  [switch]$ChangeFolder
)

$ErrorActionPreference = 'Stop'
$Repo = 'Natchez/WoW_Forever'
$Branch = 'main'
$ConfigDir = Join-Path $env:LOCALAPPDATA 'WoW_Forever'
$ConfigFile = Join-Path $ConfigDir 'addons-path.txt'

# Windows PowerShell 5.1 doesn't use TLS 1.2 by default; GitHub requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-TocVersion([string]$AddonDir) {
  $toc = Join-Path $AddonDir ((Split-Path $AddonDir -Leaf) + '.toc')
  if (-not (Test-Path -LiteralPath $toc)) { return $null }
  $m = Select-String -LiteralPath $toc -Pattern '^##\s*Version:\s*(\S+)' | Select-Object -First 1
  if ($m) { return $m.Matches[0].Groups[1].Value }
  return $null
}

# One hash for a whole folder, so we can tell whether anything changed.
function Get-FolderHash([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return '' }
  $base = (Resolve-Path -LiteralPath $Dir).Path
  $parts = Get-ChildItem -LiteralPath $Dir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($base.Length)
    $rel + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
  return ($parts -join '|')
}

function Find-AddOnsFolders {
  $roots = @(
    (Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft'),
    (Join-Path $env:ProgramFiles 'World of Warcraft'),
    (Join-Path $env:PUBLIC 'Games\World of Warcraft')
  )
  foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
    $roots += (Join-Path $drive.Root 'World of Warcraft')
    $roots += (Join-Path $drive.Root 'Games\World of Warcraft')
    $roots += (Join-Path $drive.Root 'Program Files (x86)\World of Warcraft')
    $roots += (Join-Path $drive.Root 'Program Files\World of Warcraft')
  }
  $found = @()
  foreach ($root in ($roots | Select-Object -Unique)) {
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
    # Each game version lives in a folder like _retail_, _classic_, _classic_era_, _classic_beta_
    foreach ($ver in Get-ChildItem -LiteralPath $root -Directory -Filter '_*_' -ErrorAction SilentlyContinue) {
      $addons = Join-Path $ver.FullName 'Interface\AddOns'
      if (Test-Path -LiteralPath $addons) { $found += $addons }
    }
  }
  return $found | Select-Object -Unique
}

function Choose-AddOnsFolder {
  $candidates = @(Find-AddOnsFolders)
  # Prefer a folder that already has ForeverMetrics in it
  $withFM = @($candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'ForeverMetrics') })
  if ($withFM.Count -eq 1) {
    Write-Host "Found your AddOns folder (it already has ForeverMetrics):"
    Write-Host "  $($withFM[0])"
    $ok = Read-Host 'Use this folder? (Y/n)'
    if ($ok -eq '' -or $ok -match '^[Yy]') { return $withFM[0] }
  }
  Write-Host ''
  Write-Host 'Which AddOns folder should the addons go in?'
  for ($i = 0; $i -lt $candidates.Count; $i++) {
    $mark = ''
    if (Test-Path -LiteralPath (Join-Path $candidates[$i] 'ForeverMetrics')) { $mark = '  (has ForeverMetrics)' }
    Write-Host ("  {0}) {1}{2}" -f ($i + 1), $candidates[$i], $mark)
  }
  Write-Host '  Or paste the full path to your Interface\AddOns folder.'
  while ($true) {
    $answer = (Read-Host 'Number or path').Trim().Trim('"')
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $candidates.Count) { return $candidates[$n - 1] }
    if ($answer -and (Test-Path -LiteralPath $answer -PathType Container)) { return (Resolve-Path -LiteralPath $answer).Path }
    Write-Host "That isn't a folder on this PC. Try again."
  }
}

try {
  Write-Host 'WoW_Forever addon updater' -ForegroundColor Yellow
  Write-Host ''

  # 1. Where do the addons go?
  if ($ChangeFolder -and (Test-Path -LiteralPath $ConfigFile)) { Remove-Item -LiteralPath $ConfigFile }
  if (-not $AddOnsPath -and (Test-Path -LiteralPath $ConfigFile)) {
    $AddOnsPath = (Get-Content -LiteralPath $ConfigFile -Raw).Trim()
    if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
      Write-Host "The saved AddOns folder no longer exists: $AddOnsPath"
      $AddOnsPath = $null
    }
  }
  if (-not $AddOnsPath) {
    $AddOnsPath = Choose-AddOnsFolder
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    Set-Content -LiteralPath $ConfigFile -Value $AddOnsPath -Encoding UTF8
    Write-Host "Saved. Next time it updates straight away. (Run with -ChangeFolder to pick again.)"
    Write-Host ''
  }
  Write-Host "AddOns folder: $AddOnsPath"

  # 2. Download the latest addons from GitHub
  $tmp = Join-Path $env:TEMP ('WoW_Forever_update_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'repo.zip'
  Write-Host "Downloading the latest addons from github.com/$Repo ..."
  Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
  Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x')
  $repoDir = Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory | Select-Object -First 1
  $source = Join-Path $repoDir.FullName 'addons'
  if (-not (Test-Path -LiteralPath $source)) { throw "The download has no addons folder. Has the $Branch branch been set up yet?" }

  # 3. Replace each addon folder
  Write-Host ''
  $changed = 0
  foreach ($addon in Get-ChildItem -LiteralPath $source -Directory) {
    $target = Join-Path $AddOnsPath $addon.Name
    $old = Get-TocVersion $target
    $new = Get-TocVersion $addon.FullName
    if ((Get-FolderHash $target) -eq (Get-FolderHash $addon.FullName)) {
      Write-Host ("  {0} {1}: already up to date" -f $addon.Name, $new)
      continue
    }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -LiteralPath $addon.FullName -Destination $target -Recurse
    $changed++
    if ($old) {
      Write-Host ("  {0}: {1} -> {2}" -f $addon.Name, $old, $new) -ForegroundColor Green
    } else {
      Write-Host ("  {0} {1}: installed" -f $addon.Name, $new) -ForegroundColor Green
    }
  }

  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host ''
  if ($changed -gt 0) {
    Write-Host 'Done. If WoW is open, type /reload in game to load the new version.' -ForegroundColor Yellow
  } else {
    Write-Host 'Everything is already up to date.' -ForegroundColor Yellow
  }
  exit 0
}
catch {
  Write-Host ''
  Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
  if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  exit 1
}
