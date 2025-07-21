param(
  [string]$DatabaseName,
  [string]$BackupType = "full",
  [string]$TimestampColumn = "updated_at",
  [string]$MySqlExe          = "C:\Program Files\MariaDB 11.8\bin\mysql.exe",
  [string]$MySqlDumpExe      = "C:\Program Files\MariaDB 11.8\bin\mysqldump.exe",
  [string]$MySqlUser         = "root",
  [string]$MySqlPassword     = "root@123",
  [string]$StorageAccount    = "stbackuppocc",
  [string]$StorageAccountKey = "OrrTRAlQT1e1mLKlzz0OJM5QfT5h11NE53Vq19AMlNuAYWbIjpUtCx+0lMozy8QLre2rBLgsabOb+AStY05xDA==",
  [string]$ContainerName     = "mariadb-backups",
  [string]$LocalBaseDir      = "$env:USERPROFILE\Backups\MariaDB",
  [string]$CheckpointFile    = "$env:USERPROFILE\Backups\MariaDB\LastFullCheckpoint.json"
)

#  Validate parameters 
if (-not $DatabaseName) {
  Write-Error "Missing -DatabaseName argument." ; exit 1
}
if ($BackupType -notin @("full","diff")) {
  Write-Error "Invalid -BackupType. Use 'full' or 'diff'." ; exit 1
}

#  Load Az.Storage 
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
  Install-Module Az.Storage -Scope CurrentUser -Force
}
Import-Module Az.Storage

#  Fetch available DBs 
$available = & $MySqlExe `
  --user=$MySqlUser `
  --password=$MySqlPassword `
  --batch --skip-column-names `
  -e "SHOW DATABASES;" |
  Where-Object { $_ -notin @("information_schema","performance_schema","mysql","sys") }

#  Resolve target DBs ─
if ($DatabaseName -eq "*") {
  $targets = $available
} else {
  $targets = $DatabaseName.Split(",") | ForEach-Object { $_.Trim() }
  $missing = $targets | Where-Object { $available -notcontains $_ }
  if ($missing) {
    Write-Error "These database(s) do not exist: $($missing -join ", ")" ; exit 1
  }
}

#  Prepare folders 
$now     = Get-Date
$year    = $now.ToString("yyyy")
$month   = $now.ToString("MM")
$stamp   = $now.ToString("yyyyMMdd")
$baseDir = Join-Path $LocalBaseDir $year
$monthDir= Join-Path $baseDir $month

foreach ($dir in @($LocalBaseDir, $baseDir, $monthDir)) {
  if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory | Out-Null }
}

#  Load or Save Checkpoint 
if ($BackupType -eq "full") {
  @{ LastFull = $now.ToString("o") } | ConvertTo-Json | Set-Content $CheckpointFile
} elseif ($BackupType -eq "diff") {
  if (-not (Test-Path $CheckpointFile)) {
    Write-Error "No checkpoint found. Run a full backup first." ; exit 1
  }
  $chkTime = Get-Content $CheckpointFile | ConvertFrom-Json
  $cutoff  = [DateTime]::Parse($chkTime.LastFull)
}

#  Run backup for each DB ─
foreach ($db in $targets) {
  $bakName = "${db}_${stamp}_${BackupType}.bak"
  $bakPath = Join-Path $monthDir $bakName

  if ($BackupType -eq "full") {
    Write-Host "`Full backup of '$db' → $bakPath" -ForegroundColor Cyan
    & $MySqlDumpExe `
      --user=$MySqlUser `
      --password=$MySqlPassword `
      --single-transaction `
      --routines `
      --events `
      $db > $bakPath

  } else {
    $cutoffStr = $cutoff.ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "`Differential backup of '$db' since $cutoffStr using '$TimestampColumn'" -ForegroundColor Cyan
    & $MySqlDumpExe `
      --user=$MySqlUser `
      --password=$MySqlPassword `
      --single-transaction `
      --no-create-info `
      --where="$TimestampColumn > '$cutoffStr'" `
      $db > $bakPath
  }

  if (-not (Test-Path $bakPath)) {
    Write-Error "Backup failed for '$db'. Skipping upload." ; continue
  }
  Write-Host "Backup saved locally." -ForegroundColor Green

  $ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageAccountKey

  Set-AzStorageBlobContent `
    -File $bakPath `
    -Container $ContainerName `
    -Blob $bakName `
    -Context $ctx `
    -Force | Out-Null

  Write-Host "Uploaded: https://$StorageAccount.blob.core.windows.net/$ContainerName/$bakName`n"
}

Write-Host "`All requested backups are complete!" -ForegroundColor Green
