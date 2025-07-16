# CONFIGURATION
$Database = "test"
$DbUser = "root"
$DbPassword = "root@123"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = "$env:USERPROFILE\Desktop\mariadb_backups"
$BackupFile = "${Database}_$Timestamp.sql"
$ZipFile = "${Database}_$Timestamp.zip"

# Azure Storage Info
$StorageAccount = "stbackuppocc"
$StorageKey = "OrrTRAlQT1e1mLKlzz0OJM5QfT5h11NE53Vq19AMlNuAYWbIjpUtCx+0lMozy8QLre2rBLgsabOb+AStY05xDA=="
$ContainerName = "mariadb-backups"
$BlobName = $ZipFile

# Create backup directory
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# STEP 1: Dump the MariaDB database
$DumpPath = Join-Path $BackupDir $BackupFile
$MysqlDumpExe = "C:\Program Files\MariaDB 11.8\bin\mysqldump.exe"

if (Test-Path $MysqlDumpExe) {
    & $MysqlDumpExe -u $DbUser -p"$DbPassword" $Database | Out-File $DumpPath -Encoding ascii
} else {
    Write-Host "mysqldump.exe not found at: $MysqlDumpExe"
    exit
}

# STEP 2: Compress the backup file
$ZipPath = Join-Path $BackupDir $ZipFile
if (Test-Path $DumpPath) {
    Compress-Archive -Path $DumpPath -DestinationPath $ZipPath -Force
} else {
    Write-Host "SQL dump file not found. Skipping compression."
    exit
}

# STEP 3: Create Python script to upload to Azure
$PythonScript = @"
from azure.storage.blob import BlobServiceClient
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')  # Ensure emoji works

account_name = "$StorageAccount"
account_key = "$StorageKey"
container_name = "$ContainerName"
blob_name = "$BlobName"
local_file_path = r"$ZipPath"

connection_string = f"DefaultEndpointsProtocol=https;AccountName={account_name};AccountKey={account_key};EndpointSuffix=core.windows.net"
blob_service_client = BlobServiceClient.from_connection_string(connection_string)

try:
    blob_service_client.create_container(container_name)
except:
    pass  # Container might already exist

blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
with open(local_file_path, "rb") as data:
    blob_client.upload_blob(data, overwrite=True)

print("Backup uploaded successfully!")
"@

$PythonFile = Join-Path $BackupDir "upload_to_azure.py"
$PythonScript | Out-File $PythonFile -Encoding utf8

# STEP 4: Run Python script
if (Test-Path $ZipPath) {
    python $PythonFile
} else {
    Write-Host "Zip file not found. Skipping upload."
    exit
}
