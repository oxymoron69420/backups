<#
.SYNOPSIS
  Back up a MariaDB database and upload the .bak to Azure Blob Storage using account key.

.DESCRIPTION
  - Lists MariaDB databases
  - Prompts you to pick one
  - Creates a timestamped .bak file on your Desktop
  - Uploads the .bak directly to Azure Blob Storage using Shared Key auth

.PARAMETER MySqlExe
  Full path to mysql.exe

.PARAMETER MySqlDumpExe
  Full path to mysqldump.exe

.PARAMETER MySqlUser
  MariaDB user

.PARAMETER MySqlPassword
  MariaDB password

.PARAMETER StorageAccount
  Azure Storage Account name

.PARAMETER StorageAccountKey
  Azure Storage Account key (from Access Keys)

.PARAMETER ContainerName
  Blob container name

.EXAMPLE
  PS> .\Backup-MariaDbToAzureWithKey.ps1
#>

param(
  [string]$MySqlExe          = "C:\Program Files\MariaDB 11.8\bin\mysql.exe",
  [string]$MySqlDumpExe      = "C:\Program Files\MariaDB 11.8\bin\mysqldump.exe",
  [string]$MySqlUser         = "root",
  [string]$MySqlPassword     = "root@123",
  [string]$StorageAccount    = "stbackuppocc",
  [string]$StorageAccountKey = "OrrTRAlQT1e1mLKlzz0OJM5QfT5h11NE53Vq19AMlNuAYWbIjpUtCx+0lMozy8QLre2rBLgsabOb+AStY05xDA==",
  [string]$ContainerName     = "mariadb-backups"
)

# Ensure Az.Storage is available
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
  Write-Host "Installing Az.Storage module (CurrentUser)..." -ForegroundColor Yellow
  Install-Module Az.Storage -Scope CurrentUser -Force
}
Import-Module Az.Storage

# 1) List databases
Write-Host "`nAvailable MariaDB databases:" -ForegroundColor Cyan
$databases = & $MySqlExe `
  --user=$MySqlUser `
  --password=$MySqlPassword `
  --batch `
  --skip-column-names `
  -e "SHOW DATABASES;"
$databases | ForEach-Object { Write-Host "  • $_" }

# 2) Prompt user
$dbName = Read-Host "`nEnter the database name to back up"
if ([string]::IsNullOrWhiteSpace($dbName)) {
  Write-Error "Database name cannot be empty." ; exit 1
}
if ($databases -notcontains $dbName) {
  Write-Error "Database '$dbName' not found." ; exit 1
}

# 3) Build backup filename
$timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$backupName     = "${dbName}_${timestamp}.bak"
$backupFilePath = Join-Path $env:USERPROFILE "Desktop\$backupName"

# 4) Dump the database
Write-Host "`nDumping '$dbName' to '$backupFilePath'..." -ForegroundColor Cyan
& $MySqlDumpExe `
  --user=$MySqlUser `
  --password=$MySqlPassword `
  --single-transaction `
  $dbName > $backupFilePath

if (-not (Test-Path $backupFilePath)) {
  Write-Error "Backup failed: file not created." ; exit 1
}
Write-Host "✔ Database dumped successfully." -ForegroundColor Green

# 5) Create Storage Context with Shared Key
Write-Host "`nCreating storage context with your account key..." -ForegroundColor Cyan
$ctx = New-AzStorageContext `
  -StorageAccountName $StorageAccount `
  -StorageAccountKey  $StorageAccountKey

# 6) Upload the .bak to Azure
Write-Host "Uploading '$backupName' to container '$ContainerName'..." -ForegroundColor Cyan
Set-AzStorageBlobContent `
  -File      $backupFilePath `
  -Container $ContainerName `
  -Blob      $backupName `
  -Context   $ctx `
  -Force | Out-Null

Write-Host "`n✅ Backup and upload complete!" -ForegroundColor Green
Write-Host "Your blob URL:" 
Write-Host "  https://$StorageAccount.blob.core.windows.net/$ContainerName/$backupName`n"
