#!/bin/bash
# Example Linux VM startup script
# This script runs on first boot to configure a simple web server

set -euo pipefail

# Configuration
ENVIRONMENT_TYPE="${environment_type}"
REGION="${region}"
MACHINE_TYPE="${machine_type}"
DISK_TYPE="${disk_type}"
PROJECT_ID="${project_id}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting example Linux VM configuration..."
log "Environment: $ENVIRONMENT_TYPE"
log "Region: $REGION"
log "Machine Type: $MACHINE_TYPE"
log "Disk Type: $DISK_TYPE"

# Update system packages
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install basic utilities
log "Installing basic utilities..."
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools

# Install a simple web server (nginx)
log "Installing nginx web server..."
apt-get install -y nginx

# Create a simple welcome page
log "Creating welcome page..."
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Example Linux VM</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .info {
            background-color: #f0f0f0;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>Welcome to Example Linux VM</h1>
    <div class="info">
        <h2>Instance Information</h2>
        <p><strong>Environment Type:</strong> $ENVIRONMENT_TYPE</p>
        <p><strong>Region:</strong> $REGION</p>
        <p><strong>Machine Type:</strong> $MACHINE_TYPE</p>
        <p><strong>Disk Type:</strong> $DISK_TYPE</p>
        <p><strong>Project ID:</strong> $PROJECT_ID</p>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>IP Address:</strong> $(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip -H "Metadata-Flavor: Google")</p>
    </div>
    <div class="info">
        <h2>Example Features</h2>
        <ul>
            <li>Nginx Web Server</li>
            <li>Basic system utilities</li>
            <li>Ready for custom applications</li>
        </ul>
    </div>
</body>
</html>
EOF

# Start and enable nginx
log "Starting nginx service..."
systemctl start nginx
systemctl enable nginx

# Configure firewall (if ufw is installed)
if command -v ufw &> /dev/null; then
    log "Configuring firewall..."
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 22/tcp
    ufw --force enable
fi

# Install Google Cloud SDK (if not already installed)
if ! command -v gcloud &> /dev/null; then
    log "Installing Google Cloud SDK..."
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get install -y apt-transport-https ca-certificates gnupg
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    apt-get update && apt-get install -y google-cloud-sdk
fi

# Create a health check endpoint
log "Creating health check endpoint..."
mkdir -p /var/www/html/health
cat > /var/www/html/health/index.html << EOF
{"status": "healthy", "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

log "Example Linux VM configuration completed successfully!"
log "Web server is accessible on port 80"
    Write-LogMessage "Secret: $dbaSecretName" "INFO"
    Write-LogMessage "Project ID: $projectId" "INFO"

    try {
        # Retrieve the DBA password from Secret Manager
        Write-LogMessage "Calling gcloud to retrieve DBA secret..." "INFO"
        $dbaPassword = & gcloud secrets versions access "latest" --secret="$dbaSecretName" --project="$projectId" 2>$null

        if ($LASTEXITCODE -eq 0 -and $dbaPassword) {
            Write-LogMessage "Successfully retrieved DBA password from Secret Manager" "INFO"

            # Create the DBA user account
            Write-LogMessage "Creating DBA user account..." "INFO"
            $secureDbPassword = ConvertTo-SecureString $dbaPassword -AsPlainText -Force

            # Check if DBA user already exists
            $dbaUser = Get-LocalUser -Name "DBA" -ErrorAction SilentlyContinue
            if ($dbaUser) {
                Write-LogMessage "DBA user account already exists, updating password..." "INFO"
                Set-LocalUser -Name "DBA" -Password $secureDbPassword

                # Enable the DBA account if it's disabled
                if (-not $dbaUser.Enabled) {
                    Write-LogMessage "Enabling DBA account..." "INFO"
                    Enable-LocalUser -Name "DBA"
                }
            } else {
                Write-LogMessage "Creating new DBA user account..." "INFO"
                try {
                    # Create new DBA user account
                    New-LocalUser -Name "DBA" -Password $secureDbPassword -Description "Database Administrator Account" -PasswordNeverExpires -ErrorAction Stop
                    Write-LogMessage "Created new DBA user account" "INFO"

                    # Add to Administrators group
                    Add-LocalGroupMember -Group "Administrators" -Member "DBA" -ErrorAction Stop
                    Write-LogMessage "Added DBA to Administrators group" "INFO"

                    # Add to Remote Desktop Users group
                    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "DBA" -ErrorAction SilentlyContinue
                    Write-LogMessage "Added DBA to Remote Desktop Users group" "INFO"

                    # Enable the account
                    Enable-LocalUser -Name "DBA"
                    Write-LogMessage "Enabled DBA account" "INFO"
                } catch {
                    Write-LogMessage "Failed to create DBA account: $($_.Exception.Message)" "ERROR"
                }
            }

            Write-LogMessage "DBA account configured successfully" "INFO"

            # Clear the DBA password variable from memory for security
            Clear-Variable -Name "dbaPassword" -ErrorAction SilentlyContinue
            Clear-Variable -Name "secureDbPassword" -ErrorAction SilentlyContinue

            Write-LogMessage "DBA password variables cleared from memory" "INFO"

        } else {
            Write-LogMessage "Failed to retrieve DBA password from Secret Manager (Exit code: $LASTEXITCODE)" "ERROR"
            Write-LogMessage "Ensure the secret '$dbaSecretName' exists and the service account has access" "ERROR"
        }
    } catch {
        Write-LogMessage "Error retrieving/setting DBA password: $($_.Exception.Message)" "ERROR"
        Write-LogMessage "The instance will continue with default configuration" "WARN"
    }
}

# Function to write log messages
function Write-LogMessage {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "[$Level] $Message"
    Write-Host $logEntry
    Write-EventLog -LogName Application -Source "SQL Server Setup" -EventId 1001 -EntryType Information -Message $logEntry -ErrorAction SilentlyContinue
}

# Create Windows Event Log source if it doesn't exist
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists("SQL Server Setup")) {
        New-EventLog -LogName Application -Source "SQL Server Setup"
        Write-Host "Created Windows Event Log source: SQL Server Setup"
    }
} catch {
    Write-Host "Could not create event log source: $($_.Exception.Message)"
}

Write-LogMessage "=== Starting SQL Server 2022 configuration for $EnvironmentType environment ===" "INFO"
Write-LogMessage "Instance: $InstanceName, Region: $Region, Machine: $MachineType, Disk: $DiskType" "INFO"
Write-LogMessage "GCS Bucket: $GcsBucket" "INFO"
Write-LogMessage "Admin Secret ID: $AdminSecretId" "INFO"
Write-LogMessage "DBA Secret ID: $DbaSecretId" "INFO"

# Always reset passwords on restart
Reset-Passwords -AdminSecretId $AdminSecretId -DbaSecretId $DbaSecretId

# Check if the main flag file exists (script has already run)
if (Test-Path $mainFlagFilePath) {
    Write-LogMessage "Main startup script has already been executed. Only password reset was performed." "INFO"
    exit 0
}

# Install WinFsp and rclone
Write-LogMessage "=== Installing WinFsp and rclone ===" "INFO"

# Download and install WinFsp (required for rclone mount)
$winfspUrl = "https://github.com/billziss-gh/winfsp/releases/download/v1.12.22339/winfsp-1.12.22339.msi"
$winfspInstaller = "$env:TEMP\winfsp-installer.msi"
Write-LogMessage "Downloading WinFsp v1.12 (required for rclone mount) from: $winfspUrl" "INFO"

try {
    Write-LogMessage "Starting WinFsp download..." "INFO"
    Invoke-WebRequest -Uri $winfspUrl -OutFile $winfspInstaller -UseBasicParsing
    $fileSize = (Get-Item $winfspInstaller).Length / 1MB
    Write-LogMessage "WinFsp download completed. File size: $([math]::Round($fileSize, 2)) MB" "INFO"

    Write-LogMessage "Installing WinFsp v1.12..." "INFO"
    # Install WinFsp with default configuration
    $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$winfspInstaller`" /qn /norestart" -Wait -PassThru
    Write-LogMessage "WinFsp installation completed with exit code: $($installProcess.ExitCode)" "INFO"

    if ($installProcess.ExitCode -eq 0) {
        Write-LogMessage "WinFsp v1.12 installed successfully (required for rclone mount)" "INFO"

        # Verify WinFsp installation
        $winfspService = Get-Service -Name "WinFsp" -ErrorAction SilentlyContinue
        if ($winfspService) {
            Write-LogMessage "WinFsp service found and running" "INFO"
        } else {
            Write-LogMessage "WinFsp service not found, installation may have issues" "WARN"
        }
    } else {
        Write-LogMessage "WinFsp installation may have issues. Exit code: $($installProcess.ExitCode)" "WARN"
    }

    # Clean up installer
    Remove-Item -Path $winfspInstaller -Force
    Write-LogMessage "Cleaned up WinFsp installer" "INFO"
} catch {
    Write-LogMessage "Failed to install WinFsp: $($_.Exception.Message)" "ERROR"
    throw "WinFsp installation failed: $($_.Exception.Message)"
}

# Wait for WinFsp to be fully installed
Write-LogMessage "Waiting for WinFsp to initialize..." "INFO"
Start-Sleep -Seconds 10

# Download and install rclone
Write-LogMessage "=== Installing rclone ===" "INFO"
$rcloneUrl = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$rcloneZip = "$env:TEMP\rclone-current-windows-amd64.zip"
$rcloneDir = "C:\Program Files\rclone"
Write-LogMessage "Downloading rclone from: $rcloneUrl" "INFO"

try {
    Write-LogMessage "Starting rclone download..." "INFO"
    Invoke-WebRequest -Uri $rcloneUrl -OutFile $rcloneZip -UseBasicParsing
    $fileSize = (Get-Item $rcloneZip).Length / 1MB
    Write-LogMessage "rclone download completed. File size: $([math]::Round($fileSize, 2)) MB" "INFO"

    # Create installation directory
    New-Item -ItemType Directory -Path $rcloneDir -Force
    Write-LogMessage "Created rclone installation directory: $rcloneDir" "INFO"

    # Extract the zip file
    Expand-Archive -Path $rcloneZip -DestinationPath "$env:TEMP\rclone-extract" -Force
    Write-LogMessage "Extracted rclone to temporary directory" "INFO"

    # Find the rclone executable in the extracted directory
    $extractedDir = Get-ChildItem -Path "$env:TEMP\rclone-extract" -Directory | Select-Object -First 1
    $rcloneExePath = Join-Path $extractedDir.FullName "rclone.exe"

    if (Test-Path $rcloneExePath) {
        # Copy rclone.exe to the installation directory
        Copy-Item -Path $rcloneExePath -Destination "$rcloneDir\rclone.exe" -Force
        Write-LogMessage "Copied rclone.exe to $rcloneDir" "INFO"

        # Copy manual and other files
        $manualPath = Join-Path $extractedDir.FullName "rclone.1"
        if (Test-Path $manualPath) {
            Copy-Item -Path $manualPath -Destination "$rcloneDir\rclone.1" -Force
            Write-LogMessage "Copied rclone manual" "INFO"
        }
    } else {
        throw "rclone.exe not found in extracted archive"
    }

    # Add rclone to system PATH
    $rclonePath = $rcloneDir
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$rclonePath*") {
        $newPath = "$currentPath;$rclonePath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
        $env:PATH = $newPath
        Write-LogMessage "Added rclone to system PATH: $rclonePath" "INFO"
    } else {
        Write-LogMessage "rclone already in system PATH" "INFO"
    }

    # Clean up temporary files
    Remove-Item -Path $rcloneZip -Force
    Remove-Item -Path "$env:TEMP\rclone-extract" -Recurse -Force
    Write-LogMessage "Cleaned up rclone installation files" "INFO"

    # Verify rclone installation
    $rcloneExe = "$rcloneDir\rclone.exe"
    if (Test-Path $rcloneExe) {
        Write-LogMessage "rclone installed successfully at: $rcloneExe" "INFO"

        # Test rclone executable
        try {
            $versionOutput = & $rcloneExe version 2>&1
            Write-LogMessage "rclone version check successful" "INFO"
        } catch {
            Write-LogMessage "Warning: rclone version check failed: $($_.Exception.Message)" "WARN"
        }
    } else {
        throw "rclone.exe not found after installation"
    }

    # Configure rclone for Google Cloud Storage
    Write-LogMessage "=== Configuring rclone for Google Cloud Storage ===" "INFO"

    # Create rclone config directory at specified location
    $rcloneConfigDir = "C:\Users\Administrator\AppData\Roaming\rclone"
    New-Item -ItemType Directory -Path $rcloneConfigDir -Force
    Write-LogMessage "Created rclone config directory: $rcloneConfigDir" "INFO"

    # Create rclone configuration for GCS with specified template
    $rcloneConfig = @"
[gcs]
type = google cloud storage
project_number = org-test-dev
object_acl = private
bucket_acl = private
location = europe-west2
storage_class = REGIONAL
env_auth = true
"@

    $configPath = "$rcloneConfigDir\rclone.conf"
    Set-Content -Path $configPath -Value $rcloneConfig -Encoding UTF8
    Write-LogMessage "Created rclone configuration file: $configPath" "INFO"
    Write-LogMessage "Configuration includes project: org-test-dev, location: europe-west2, auth: env_auth" "INFO"

         # Create mount script for GCS bucket
     $mountScriptContent = @"
@echo off
REM Wait for network connectivity
:NETWORK_CHECK
ping -n 1 storage.googleapis.com >nul 2>&1
if errorlevel 1 (
    echo Waiting for network connectivity...
    timeout /t 5 /nobreak >nul
    goto NETWORK_CHECK
)

REM Mount GCS bucket using rclone
echo Mounting GCS bucket $GcsBucket to V: drive...
"$rcloneDir\rclone.exe" mount gcs:$GcsBucket V: --vfs-cache-mode writes --log-file "C:\Scripts\rclone-mount.log" --log-level INFO

if errorlevel 1 (
    echo Failed to mount GCS bucket
    exit /b 1
) else (
    echo Successfully mounted GCS bucket $GcsBucket to V: drive
)
"@

     $mountScriptPath = "C:\Scripts\mount-gcs-bucket.bat"
     New-Item -ItemType Directory -Path "C:\Scripts" -Force
     Set-Content -Path $mountScriptPath -Value $mountScriptContent -Encoding ASCII
     Write-LogMessage "Created rclone mount script: $mountScriptPath" "INFO"

         # Configure rclone as a Windows service using built-in service integration
     Write-LogMessage "Configuring rclone mount as Windows service using built-in integration..." "INFO"
     $serviceName = "Rclone"
     $serviceDisplayName = "Rclone GCS Mount Service"
     $serviceDescription = "Mounts Google Cloud Storage buckets using rclone built-in service integration"

     # Create logs directory for rclone
     $rcloneLogsDir = "C:\rclone\logs"
     New-Item -ItemType Directory -Path $rcloneLogsDir -Force
     Write-LogMessage "Created rclone logs directory: $rcloneLogsDir" "INFO"

     # Check if service already exists
     $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
     if ($existingService) {
         Write-LogMessage "Service $serviceName already exists, removing..." "INFO"
         Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
         Start-Sleep -Seconds 2
         Remove-Service -Name $serviceName -ErrorAction SilentlyContinue
         Start-Sleep -Seconds 2
     }

     # Create the service using New-Service with rclone's built-in service integration
     $rcloneMountCmd = "`"$rcloneExe`" mount gcs:$GcsBucket V: --config `"$configPath`" --vfs-cache-mode writes --log-file `"$rcloneLogsDir\mount.log`" --log-level INFO"

     Write-LogMessage "Creating Windows service for rclone mount using built-in integration..." "INFO"
     Write-LogMessage "Service command: $rcloneMountCmd" "INFO"

     try {
         # Create service using New-Service (rclone's built-in service integration)
         $service = New-Service -Name $serviceName `
                               -BinaryPathName $rcloneMountCmd `
                               -DisplayName $serviceDisplayName `
                               -Description $serviceDescription `
                               -StartupType Automatic `
                               -ErrorAction Stop

         Write-LogMessage "Service created successfully using rclone built-in integration" "INFO"

         # Configure service to restart on failure using sc.exe
         Write-LogMessage "Configuring service recovery actions..." "INFO"
         $scResult = & sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000
         if ($LASTEXITCODE -eq 0) {
             Write-LogMessage "Service recovery actions configured successfully" "INFO"
         } else {
             Write-LogMessage "Warning: Failed to configure service recovery actions. Exit code: $LASTEXITCODE" "WARN"
         }

         # Start the service with error handling
         Write-LogMessage "Starting rclone mount service..." "INFO"
         try {
             Start-Service -Name $serviceName -ErrorAction Stop
             Write-LogMessage "Service started successfully" "INFO"
         } catch {
             Write-LogMessage "Failed to start service: $($_.Exception.Message)" "ERROR"
             Write-LogMessage "Service will be configured to start automatically on boot" "INFO"
         }

         Write-LogMessage "Waiting 15 seconds for service to initialize..." "INFO"
         Start-Sleep -Seconds 15

         # Verify service status
         $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
         if ($service) {
             Write-LogMessage "Service status: $($service.Status)" "INFO"
         }

         # Verify mount
         if (Test-Path "V:\") {
             Write-LogMessage "Successfully mounted GCS bucket $GcsBucket to V: drive using rclone built-in service integration" "INFO"
             try {
                 $mountInfo = Get-ChildItem "V:\" -ErrorAction SilentlyContinue | Measure-Object
                 Write-LogMessage "GCS bucket mount verified. Items in bucket: $($mountInfo.Count)" "INFO"
             } catch {
                 Write-LogMessage "GCS bucket mounted but could not enumerate contents (may be empty or permissions issue)" "WARN"
             }
         } else {
             Write-LogMessage "V: drive not accessible, mount may have failed" "WARN"
             Write-LogMessage "Service will retry automatically on boot" "INFO"
         }
     } catch {
         Write-LogMessage "Failed to create service using built-in integration: $($_.Exception.Message)" "ERROR"
     }

         # Create a scheduled task as fallback
     $taskName = "MountGCSBucketRclone"
     Write-LogMessage "Creating fallback scheduled task: $taskName" "INFO"

     $fallbackScript = @"
# Wait for network connectivity
do {
    Start-Sleep -Seconds 5
    `$ping = Test-NetConnection -ComputerName "storage.googleapis.com" -Port 443 -InformationLevel Quiet
} while (-not `$ping)

# Check if service is running
`$service = Get-Service -Name "Rclone" -ErrorAction SilentlyContinue
if (`$service -and `$service.Status -ne 'Running') {
    Start-Service -Name "Rclone"
    Write-Host "Started rclone mount service"
} else {
    Write-Host "rclone mount service is already running or not found"
}

# Alternative: Direct mount if service fails
if (-not (Test-Path "V:\")) {
    Write-Host "V: drive not found, attempting direct mount..."
    Start-Process -FilePath "$rcloneDir\rclone.exe" -ArgumentList "mount", "gcs:$GcsBucket", "V:", "--config", "$configPath", "--vfs-cache-mode", "writes", "--daemon" -WindowStyle Hidden
}
"@

    $fallbackScriptPath = "C:\Scripts\mount-gcs-bucket-rclone.ps1"
    Set-Content -Path $fallbackScriptPath -Value $fallbackScript

    # Create scheduled task to run at startup
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$fallbackScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    try {
        Write-LogMessage "Registering fallback scheduled task: $taskName" "INFO"
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
        Write-LogMessage "Fallback scheduled task '$taskName' created successfully" "INFO"
    } catch {
        Write-LogMessage "Failed to create fallback scheduled task: $($_.Exception.Message)" "ERROR"
    }

    Write-LogMessage "rclone installation and configuration completed successfully" "INFO"
} catch {
    Write-LogMessage "Failed to install rclone: $($_.Exception.Message)" "ERROR"
}

# Initialize and format secondary disks
Write-LogMessage "=== Initializing and formatting secondary disks ===" "INFO"

# Get all disks that are not initialized
$uninitializedDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }
Write-LogMessage "Scanning for uninitialized disks..." "INFO"

# Log all available disks
$allDisks = Get-Disk
Write-LogMessage "Total disks found: $($allDisks.Count)" "INFO"
foreach ($disk in $allDisks) {
    Write-LogMessage "Disk $($disk.Number): $($disk.FriendlyName), Size: $([math]::Round($disk.Size/1GB, 2))GB, Status: $($disk.PartitionStyle)" "INFO"
}

if ($uninitializedDisks.Count -gt 0) {
    Write-LogMessage "Found $($uninitializedDisks.Count) uninitialized disk(s) to format" "INFO"

    $driveLetters = @('D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'W', 'X', 'Y', 'Z')
    $driveIndex = 0

    foreach ($disk in $uninitializedDisks) {
        try {
            $diskNumber = $disk.Number
            $driveLetter = $driveLetters[$driveIndex]
            $diskSize = [math]::Round($disk.Size/1GB, 2)

            Write-LogMessage "Processing disk $diskNumber ($($disk.FriendlyName), $($diskSize)GB) as drive $driveLetter" "INFO"

            # Initialize the disk with GPT partition style
            Write-LogMessage "Initializing disk $diskNumber with GPT partition style..." "INFO"
            Initialize-Disk -Number $diskNumber -PartitionStyle GPT -Confirm:$false
            Write-LogMessage "Disk $diskNumber initialized successfully" "INFO"

            # Create a new partition using the entire disk
            Write-LogMessage "Creating partition on disk $diskNumber..." "INFO"
            $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -DriveLetter $driveLetter
            Write-LogMessage "Partition created with drive letter $driveLetter" "INFO"

            # Format the partition as NTFS
            Write-LogMessage "Formatting drive $driveLetter with NTFS..." "INFO"
            Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel "SQL-Data-$driveLetter" -Confirm:$false
            Write-LogMessage "Drive $driveLetter formatted successfully" "INFO"

            Write-LogMessage "Successfully initialized disk $diskNumber as drive $driveLetter`: ($($diskSize)GB)" "INFO"

            # Set up SQL Server directories on the first additional disk (D:)
            if ($driveLetter -eq 'D') {
                Write-LogMessage "Setting up SQL Server directories on drive $driveLetter..." "INFO"
                $sqlDataDir = "$driveLetter`:\SQLServerData"
                $sqlLogDir = "$driveLetter`:\SQLServerLogs"
                $sqlTempDir = "$driveLetter`:\SQLServerTemp"

                @($sqlDataDir, $sqlLogDir, $sqlTempDir) | ForEach-Object {
                    if (!(Test-Path $_)) {
                        Write-LogMessage "Creating SQL Server directory: $_" "INFO"
                        New-Item -ItemType Directory -Path $_ -Force
                        Write-LogMessage "Created SQL Server directory: $_" "INFO"
                    } else {
                        Write-LogMessage "SQL Server directory already exists: $_" "INFO"
                    }
                }

                # Set permissions for SQL Server service account
                Write-LogMessage "Setting permissions for SQL Server service accounts..." "INFO"
                $sqlServiceAccount = "NT SERVICE\MSSQLSERVER"
                $sqlAgentAccount = "NT SERVICE\SQLSERVERAGENT"
                Write-LogMessage "SQL Service Account: $sqlServiceAccount" "INFO"
                Write-LogMessage "SQL Agent Account: $sqlAgentAccount" "INFO"

                foreach ($dir in @($sqlDataDir, $sqlLogDir, $sqlTempDir)) {
                    try {
                        Write-LogMessage "Setting permissions on directory: $dir" "INFO"
                        $acl = Get-Acl $dir
                        $accessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($sqlServiceAccount, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                        $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($sqlAgentAccount, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                        $acl.SetAccessRule($accessRule1)
                        $acl.SetAccessRule($accessRule2)
                        Set-Acl -Path $dir -AclObject $acl
                        Write-LogMessage "Successfully set permissions for SQL Server on directory: $dir" "INFO"
                    } catch {
                        Write-LogMessage "Warning: Failed to set permissions on $dir - $($_.Exception.Message)" "WARN"
                    }
                }
            }

            $driveIndex++
            Write-LogMessage "Disk $diskNumber processing completed. Drive index incremented to $driveIndex" "INFO"
        } catch {
            Write-LogMessage "Error initializing disk $diskNumber`: $($_.Exception.Message)" "ERROR"
        }
    }
    Write-LogMessage "Completed processing $($uninitializedDisks.Count) uninitialized disks" "INFO"
} else {
    Write-LogMessage "No uninitialized disks found" "INFO"

    # Check if D: drive already exists and create SQL directories if needed
    if (Test-Path "D:\") {
        Write-LogMessage "D: drive already exists, setting up SQL Server directories..." "INFO"
        $sqlDataDir = "D:\SQLServerData"
        $sqlLogDir = "D:\SQLServerLogs"
        $sqlTempDir = "D:\SQLServerTemp"

        @($sqlDataDir, $sqlLogDir, $sqlTempDir) | ForEach-Object {
            if (!(Test-Path $_)) {
                Write-LogMessage "Creating SQL Server directory: $_" "INFO"
                New-Item -ItemType Directory -Path $_ -Force
                Write-LogMessage "Created SQL Server directory: $_" "INFO"
            } else {
                Write-LogMessage "SQL Server directory already exists: $_" "INFO"
            }
        }
    } else {
        Write-LogMessage "D: drive not found - no additional disks available" "INFO"
    }
}

# Log disk configuration
Write-LogMessage "=== Final Disk Configuration ===" "INFO"
try {
    $diskInfo = Get-Disk | ForEach-Object {
        "Disk $($_.Number): $($_.FriendlyName), Size: $([math]::Round($_.Size/1GB, 2))GB, Status: $($_.PartitionStyle), Health: $($_.OperationalStatus)"
    }
    $diskInfo | ForEach-Object { Write-LogMessage $_ "INFO" }

    $volumeInfo = Get-Volume | Where-Object {$_.DriveLetter -ne $null} | ForEach-Object {
        "Volume $($_.DriveLetter): Label=$($_.FileSystemLabel), Size=$([math]::Round($_.Size/1GB, 2))GB, Free=$([math]::Round($_.SizeRemaining/1GB, 2))GB, FS=$($_.FileSystem)"
    }
    $volumeInfo | ForEach-Object { Write-LogMessage $_ "INFO" }
} catch {
    Write-LogMessage "Error retrieving disk configuration: $($_.Exception.Message)" "ERROR"
}

# Enable and configure Remote Desktop
Write-LogMessage "=== Configuring Remote Desktop ===" "INFO"
Write-LogMessage "Enabling Remote Desktop connections..." "INFO"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Write-LogMessage "Enabling Remote Desktop firewall rule..." "INFO"
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Write-LogMessage "Configuring RDP authentication..." "INFO"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
Write-LogMessage "Remote Desktop enabled and configured successfully" "INFO"

# Install and configure OpenSSH Server
Write-LogMessage "=== Installing and configuring OpenSSH Server ===" "INFO"
# Check if OpenSSH is installed
$sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if (-not $sshService) {
    Write-LogMessage "OpenSSH Server not found, installing..." "INFO"
    # Install OpenSSH Server
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-LogMessage "OpenSSH Server installation completed" "INFO"
} else {
    Write-LogMessage "OpenSSH Server already installed" "INFO"
}

# Start and configure SSH service
Write-LogMessage "Starting SSH service..." "INFO"
Start-Service sshd
Write-LogMessage "Setting SSH service to automatic startup..." "INFO"
Set-Service -Name sshd -StartupType Automatic
Write-LogMessage "Enabling SSH firewall rule..." "INFO"
Enable-NetFirewallRule -DisplayName "OpenSSH SSH Server (sshd)"
Write-LogMessage "OpenSSH Server configured and started successfully" "INFO"

# Enable Windows Firewall exceptions for SQL Server
Write-LogMessage "=== Configuring Windows Firewall for SQL Server ===" "INFO"

# Define SQL Server firewall rules
$sqlFirewallRules = @(
    @{
        Name = "SQL Server Database Engine"
        DisplayName = "SQL Server Database Engine (TCP-1433)"
        Protocol = "TCP"
        LocalPort = 1433
        Description = "Allow inbound connections to SQL Server Database Engine"
    },
    @{
        Name = "SQL Server Browser"
        DisplayName = "SQL Server Browser Service (UDP-1434)"
        Protocol = "UDP"
        LocalPort = 1434
        Description = "Allow inbound connections to SQL Server Browser Service"
    },
    @{
        Name = "SQL Server Analysis Services"
        DisplayName = "SQL Server Analysis Services (TCP-2383)"
        Protocol = "TCP"
        LocalPort = 2383
        Description = "Allow inbound connections to SQL Server Analysis Services"
    },
    @{
        Name = "SQL Server Reporting Services"
        DisplayName = "SQL Server Reporting Services (TCP-80)"
        Protocol = "TCP"
        LocalPort = 80
        Description = "Allow inbound connections to SQL Server Reporting Services (HTTP)"
    },
    @{
        Name = "SQL Server Reporting Services SSL"
        DisplayName = "SQL Server Reporting Services SSL (TCP-443)"
        Protocol = "TCP"
        LocalPort = 443
        Description = "Allow inbound connections to SQL Server Reporting Services (HTTPS)"
    },
    @{
        Name = "SQL Server Integration Services"
        DisplayName = "SQL Server Integration Services (TCP-135)"
        Protocol = "TCP"
        LocalPort = 135
        Description = "Allow inbound connections to SQL Server Integration Services"
    }
)

# Create firewall rules for SQL Server
foreach ($rule in $sqlFirewallRules) {
    try {
        Write-LogMessage "Creating firewall rule: $($rule.DisplayName)..." "INFO"

        # Check if rule already exists
        $existingRule = Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        if ($existingRule) {
            Write-LogMessage "Firewall rule '$($rule.DisplayName)' already exists, updating..." "INFO"
            Set-NetFirewallRule -DisplayName $rule.DisplayName -Action Allow -Enabled True
        } else {
            # Create new firewall rule
            New-NetFirewallRule -DisplayName $rule.DisplayName `
                               -Direction Inbound `
                               -Protocol $rule.Protocol `
                               -LocalPort $rule.LocalPort `
                               -Action Allow `
                               -Profile Any `
                               -Description $rule.Description `
                               -ErrorAction Stop
            Write-LogMessage "Successfully created firewall rule: $($rule.DisplayName)" "INFO"
        }
    } catch {
        Write-LogMessage "Failed to create firewall rule '$($rule.DisplayName)': $($_.Exception.Message)" "WARN"
    }
}

# Enable SQL Server specific program rules
Write-LogMessage "Configuring SQL Server executable firewall rules..." "INFO"
$sqlExecutables = @(
    @{
        Program = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
        DisplayName = "SQL Server Database Engine Process"
        Description = "Allow SQL Server Database Engine process through firewall"
    },
    @{
        Program = "C:\Program Files\Microsoft SQL Server\90\Shared\sqlbrowser.exe"
        DisplayName = "SQL Server Browser Process"
        Description = "Allow SQL Server Browser process through firewall"
    },
    @{
        Program = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\SQLAGENT.EXE"
        DisplayName = "SQL Server Agent Process"
        Description = "Allow SQL Server Agent process through firewall"
    }
)

foreach ($exe in $sqlExecutables) {
    if (Test-Path $exe.Program) {
        try {
            Write-LogMessage "Creating executable firewall rule for: $($exe.DisplayName)..." "INFO"

            # Check if rule already exists
            $existingExeRule = Get-NetFirewallRule -DisplayName $exe.DisplayName -ErrorAction SilentlyContinue
            if ($existingExeRule) {
                Write-LogMessage "Executable rule '$($exe.DisplayName)' already exists, updating..." "INFO"
                Set-NetFirewallRule -DisplayName $exe.DisplayName -Action Allow -Enabled True
            } else {
                New-NetFirewallRule -DisplayName $exe.DisplayName `
                                   -Direction Inbound `
                                   -Program $exe.Program `
                                   -Action Allow `
                                   -Profile Any `
                                   -Description $exe.Description `
                                   -ErrorAction Stop
                Write-LogMessage "Successfully created executable rule: $($exe.DisplayName)" "INFO"
            }
        } catch {
            Write-LogMessage "Failed to create executable rule '$($exe.DisplayName)': $($_.Exception.Message)" "WARN"
        }
    } else {
        Write-LogMessage "SQL Server executable not found: $($exe.Program)" "WARN"
    }
}

# Configure Windows Firewall to allow SQL Server through Windows Defender Firewall
Write-LogMessage "Configuring Windows Defender Firewall for SQL Server..." "INFO"
try {
    # Enable the built-in SQL Server firewall rule groups if they exist
    $sqlRuleGroups = @(
        "SQL Server",
        "SQL Server Database Engine",
        "SQL Server Browser"
    )

    foreach ($group in $sqlRuleGroups) {
        try {
            Enable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
            Write-LogMessage "Enabled firewall rule group: $group" "INFO"
        } catch {
            Write-LogMessage "Firewall rule group '$group' not found or already enabled" "INFO"
        }
    }
} catch {
    Write-LogMessage "Error configuring Windows Defender Firewall groups: $($_.Exception.Message)" "WARN"
}

# Verify firewall rules were created successfully
Write-LogMessage "Verifying SQL Server firewall configuration..." "INFO"
try {
    $sqlRules = Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*SQL*" -and $_.Enabled -eq $true }
    Write-LogMessage "Active SQL Server firewall rules count: $($sqlRules.Count)" "INFO"

    foreach ($rule in $sqlRules) {
        Write-LogMessage "Active rule: $($rule.DisplayName) - $($rule.Direction)" "INFO"
    }
} catch {
    Write-LogMessage "Could not verify firewall rules: $($_.Exception.Message)" "WARN"
}

Write-LogMessage "SQL Server firewall configuration completed" "INFO"

# Configure SQL Server services
Write-LogMessage "=== Configuring SQL Server services ===" "INFO"
try {
    Write-LogMessage "Setting MSSQLSERVER service to automatic startup..." "INFO"
    Set-Service -Name "MSSQLSERVER" -StartupType Automatic -ErrorAction Stop
    Write-LogMessage "MSSQLSERVER service configured for automatic startup" "INFO"
} catch {
    Write-LogMessage "Failed to configure MSSQLSERVER service: $($_.Exception.Message)" "WARN"
}

try {
    Write-LogMessage "Setting SQLSERVERAGENT service to automatic startup..." "INFO"
    Set-Service -Name "SQLSERVERAGENT" -StartupType Automatic -ErrorAction Stop
    Write-LogMessage "SQLSERVERAGENT service configured for automatic startup" "INFO"
} catch {
    Write-LogMessage "Failed to configure SQLSERVERAGENT service: $($_.Exception.Message)" "WARN"
}

# Start SQL Server services if not already running
Write-LogMessage "=== Starting SQL Server services ===" "INFO"
try {
    Write-LogMessage "Starting MSSQLSERVER service..." "INFO"
    Start-Service -Name "MSSQLSERVER" -ErrorAction Stop
    $sqlService = Get-Service -Name "MSSQLSERVER"
    Write-LogMessage "MSSQLSERVER service status: $($sqlService.Status)" "INFO"
} catch {
    Write-LogMessage "Failed to start MSSQLSERVER service: $($_.Exception.Message)" "WARN"
}

try {
    Write-LogMessage "Starting SQLSERVERAGENT service..." "INFO"
    Start-Service -Name "SQLSERVERAGENT" -ErrorAction Stop
    $agentService = Get-Service -Name "SQLSERVERAGENT"
    Write-LogMessage "SQLSERVERAGENT service status: $($agentService.Status)" "INFO"
} catch {
    Write-LogMessage "Failed to start SQLSERVERAGENT service: $($_.Exception.Message)" "WARN"
}


# Configure SQL Server logins
Write-LogMessage "=== Configuring SQL Server Logins ===" "INFO"

# Wait for SQL Server to be fully started
Write-LogMessage "Waiting for SQL Server to be fully started..." "INFO"
Start-Sleep -Seconds 30

# Function to execute SQL commands
function Invoke-SqlCommand {
    param(
        [string]$Query,
        [string]$Server = "localhost",
        [string]$Database = "master"
    )
    try {
        $result = Invoke-Sqlcmd -Query $Query -ServerInstance $Server -Database $Database -ErrorAction Stop
        return $result
    } catch {
        Write-LogMessage "SQL Command failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Check if DBA Windows login exists and create if it doesn't
$dbaWindowsUser = "DOMAIN\DBA"
Write-LogMessage "Checking for DBA Windows login: $dbaWindowsUser..." "INFO"
$dbaLoginCheck = Invoke-SqlCommand -Query "SELECT name FROM sys.server_principals WHERE name = '$dbaWindowsUser'"
if (-not $dbaLoginCheck) {
    Write-LogMessage "Creating DBA Windows Authentication login..." "INFO"

    try {
        # Create SQL Server Windows Authentication login for DBA
        $createLoginQuery = @"
CREATE LOGIN [$dbaWindowsUser] FROM WINDOWS
    WITH DEFAULT_DATABASE = [master];
ALTER SERVER ROLE [sysadmin] ADD MEMBER [$dbaWindowsUser];
"@
        Invoke-SqlCommand -Query $createLoginQuery
        Write-LogMessage "Successfully created DBA Windows login '$dbaWindowsUser' and added to sysadmin role" "INFO"

    } catch {
        Write-LogMessage "Error creating DBA Windows login: $($_.Exception.Message)" "ERROR"
        Write-LogMessage "Note: Ensure the Windows user '$dbaWindowsUser' exists and SQL Server can authenticate it" "WARN"
    }
} else {
    Write-LogMessage "DBA Windows login '$dbaWindowsUser' already exists" "INFO"
}

# Create additional SQL Server directories
Write-LogMessage "=== Setting up remaining SQL Server directories ===" "INFO"
$logDir = "E:\SQLServerLogs"
$backupDir = "E:\SQLServerBackups"
$dataDir = if (Test-Path "D:\SQLServerData") { "D:\SQLServerData" } else { "C:\SQLServerData" }
Write-LogMessage "Primary data directory: $dataDir" "INFO"

@($logDir, $backupDir) | ForEach-Object {
    if (!(Test-Path $_)) {
        Write-LogMessage "Creating directory: $_" "INFO"
        New-Item -ItemType Directory -Path $_ -Force
        Write-LogMessage "Created directory: $_" "INFO"
    } else {
        Write-LogMessage "Directory already exists: $_" "INFO"
    }
}

# Ensure fallback data directory exists if D: drive setup failed
if (!(Test-Path $dataDir)) {
    Write-LogMessage "Primary data directory not found, creating fallback..." "WARN"
    New-Item -ItemType Directory -Path "C:\SQLServerData" -Force
    $dataDir = "C:\SQLServerData"
    Write-LogMessage "Created fallback data directory: $dataDir" "INFO"
} else {
    Write-LogMessage "Data directory verified: $dataDir" "INFO"
}

# Configure SQL Server memory and other settings
Write-LogMessage "=== Finalizing SQL Server Configuration ===" "INFO"
# This would typically be done via SQL commands, but for basic setup:
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Set up Windows Updates (disable automatic updates for SQL Server stability)
Write-LogMessage "Configuring Windows Updates (disabling automatic updates for stability)..." "INFO"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 2 -ErrorAction Stop
    Write-LogMessage "Windows Update automatic updates disabled" "INFO"
} catch {
    Write-LogMessage "Failed to configure Windows Updates: $($_.Exception.Message)" "WARN"
}

# Generate comprehensive configuration summary
$dbaUserStatus = if ($DbaSecretId -and $DbaSecretId -ne "") {
    $dbaUser = Get-LocalUser -Name "DBA" -ErrorAction SilentlyContinue
    if ($dbaUser) { "Created successfully" } else { "Creation failed" }
} else { "Not configured" }

$configSummary = @"
SQL Server 2022 startup configuration completed at $timestamp
Environment: $EnvironmentType
Instance: $InstanceName
Region: $Region
Machine Type: $MachineType
Disk Type: $DiskType
Remote Access: RDP and SSH enabled
Admin Password: Retrieved from Secret Manager ($AdminSecretId)
DBA User Account: $dbaUserStatus$(if ($DbaSecretId -and $DbaSecretId -ne "") { " (Secret: $DbaSecretId)" } else { "" })
GCS Bucket: $GcsBucket mounted via rclone to V: drive$(if (Test-Path "V:\") { " (active)" } else { " (service configured)" })
SQL Data Directory: $dataDir
Secondary Disks: $(if (Test-Path "D:\") { "D: drive configured" } else { "No additional disks" })
Services Status: SQL Server and rclone mount configured for automatic startup
Network Access: Firewall rules configured for SQL Server (1433) and SQL Browser (1434)
"@

Write-LogMessage "=== CONFIGURATION SUMMARY ===" "INFO"
$configSummary -split "`n" | ForEach-Object {
    if ($_.Trim()) { Write-LogMessage $_.Trim() "INFO" }
}

# Save summary to file
try {
    Add-Content -Path "$logDir\startup.log" -Value $configSummary
    Write-LogMessage "Configuration summary saved to: $logDir\startup.log" "INFO"
} catch {
    Write-LogMessage "Failed to save configuration summary: $($_.Exception.Message)" "WARN"
}

# Additional SQL Server configuration can be added here
Write-LogMessage "Additional configuration options available:" "INFO"
Write-LogMessage "- Configure SQL Server authentication mode" "INFO"
Write-LogMessage "- Set up database file locations" "INFO"
Write-LogMessage "- Configure backup schedules" "INFO"
Write-LogMessage "- Set up monitoring" "INFO"

Write-LogMessage "=== SQL Server 2022 configuration completed successfully ===" "INFO"

# Log completion to Windows Event Log
try {
    Write-EventLog -LogName Application -Source "SQL Server Setup" -EventId 1000 -EntryType Information -Message "SQL Server 2022 startup configuration completed successfully for $EnvironmentType environment at $timestamp" -ErrorAction Stop
    Write-LogMessage "Configuration completion logged to Windows Event Log" "INFO"
} catch {
    Write-LogMessage "Failed to write to Windows Event Log: $($_.Exception.Message)" "WARN"
}

Write-LogMessage "Startup script execution completed. Check Google Cloud Console logs for full details." "INFO"

# Create the flag file to indicate script has completed successfully
try {
    # Ensure the Scripts directory exists
    $scriptsDir = Split-Path -Parent $mainFlagFilePath
    if (!(Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force
        Write-LogMessage "Created Scripts directory: $scriptsDir" "INFO"
    }

    # Create the flag file
    $null = New-Item -Path $mainFlagFilePath -ItemType File -Force
    Write-LogMessage "Flag file created: $mainFlagFilePath" "INFO"
    Write-LogMessage "Script will not run again on subsequent boots (except password reset)" "INFO"
} catch {
    Write-LogMessage "Failed to create flag file: $($_.Exception.Message)" "WARN"
}
