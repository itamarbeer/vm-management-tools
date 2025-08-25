#!/usr/bin/pwsh
# vCenter Credentials Manager v2.0
# Enhanced version for project-vc-manage
# This script creates and manages encrypted credentials for connecting to vCenter servers

# Import required modules
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
} catch {
    Write-Error "Failed to import PowerCLI module. Is it installed? Error: $_"
    exit 1
}

# Configuration - Updated paths for new project structure
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$CredentialKeyFile = Join-Path $ProjectRoot "secure/credential_key.key"
$CredentialStore = Join-Path $ProjectRoot "secure/vcenter_credentials.enc"
$LogFile = Join-Path $ProjectRoot "logs/credential-update.log"

# Ensure directories exist
$SecureDir = Split-Path -Path $CredentialKeyFile -Parent
$LogDir = Split-Path -Path $LogFile -Parent

if (-not (Test-Path $SecureDir)) {
    New-Item -Path $SecureDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Function to write to log file
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $LogFile -Value $LogEntry -ErrorAction Stop
    } catch {
        Write-Host "Failed to write to log: $_" -ForegroundColor Red
    }
    
    # Output to console with color
    switch ($Level) {
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        default { Write-Host $LogEntry }
    }
}

# Function to get or create encryption key
function Get-EncryptionKey {
    if (Test-Path $CredentialKeyFile) {
        try {
            $Key = Get-Content $CredentialKeyFile -ErrorAction Stop
            Write-Log "Encryption key loaded successfully" -Level "SUCCESS"
            return $Key
        } catch {
            Write-Log "Error reading encryption key: $_" -Level "ERROR"
            exit 1
        }
    } else {
        Write-Log "Creating new encryption key..." -Level "INFO"
        
        # Generate a secure random key
        $AESKey = New-Object Byte[] 32
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($AESKey)
        $Key = [System.Convert]::ToBase64String($AESKey)
        
        # Save the key
        try {
            Set-Content -Path $CredentialKeyFile -Value $Key -ErrorAction Stop
            Write-Log "Encryption key created and saved" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to save encryption key: $_" -Level "ERROR"
            exit 1
        }
        
        # Set restrictive permissions on key file
        if ($IsWindows) {
            try {
                $Acl = Get-Acl -Path $CredentialKeyFile
                $Acl.SetAccessRuleProtection($true, $false)
                $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUser, "FullControl", "Allow")
                $Acl.AddAccessRule($AccessRule)
                Set-Acl -Path $CredentialKeyFile -AclObject $Acl
                Write-Log "Windows file permissions set for key file" -Level "SUCCESS"
            } catch {
                Write-Log "Warning: Could not set Windows file permissions: $_" -Level "WARNING"
            }
        } else {
            # For Linux/macOS, use chmod
            try {
                chmod 600 $CredentialKeyFile
                Write-Log "Unix file permissions set for key file (600)" -Level "SUCCESS"
            } catch {
                Write-Log "Warning: Could not set Unix file permissions: $_" -Level "WARNING"
            }
        }
        
        return $Key
    }
}

# Function to load existing credentials
function Get-ExistingVCenterCredentials {
    # Check if credential store exists
    if (-not (Test-Path $CredentialStore)) {
        Write-Log "Credential store not found. Will create a new one." -Level "WARNING"
        return @{}
    }
    
    try {
        # Get encryption key
        $Key = Get-EncryptionKey
        
        # Load encrypted credentials
        $EncryptedData = Get-Content -Path $CredentialStore -Raw | ConvertFrom-Json
        
        $Credentials = @{}
        
        # Process each server's credentials
        $EncryptedData.PSObject.Properties | ForEach-Object {
            $server = $_.Name
            $data = $_.Value
            
            try {
                $username = $data.Username
                $securePassword = $data.Password | ConvertTo-SecureString -Key ([System.Convert]::FromBase64String($Key))
                
                $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
                $Credentials[$server] = $credential
                
                Write-Log "Loaded credentials for $server" -Level "SUCCESS"
            } catch {
                Write-Log "Error processing credentials for $server : $_" -Level "ERROR"
            }
        }
        
        return $Credentials
    } catch {
        Write-Log "Error loading credentials: $_" -Level "ERROR"
        return @{}
    }
}

# Function to save credentials to encrypted store
function Save-VCenterCredentials {
    param (
        [hashtable]$Credentials
    )
    
    try {
        $Key = Get-EncryptionKey
        
        # Convert credentials to a secure format
        $EncryptedData = @{}
        
        foreach ($server in $Credentials.Keys) {
            $username = $Credentials[$server].UserName
            $password = $Credentials[$server].Password | ConvertFrom-SecureString -Key ([System.Convert]::FromBase64String($Key))
            
            $EncryptedData[$server] = @{
                Username = $username
                Password = $password
            }
        }
        
        # Save encrypted credentials
        $EncryptedData | ConvertTo-Json -Depth 3 | Set-Content -Path $CredentialStore -ErrorAction Stop
        
        # Set secure permissions on credential store
        if (-not $IsWindows) {
            chmod 600 $CredentialStore
        }
        
        Write-Log "Credential store saved successfully to $CredentialStore" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-Log "Error saving credentials: $_" -Level "ERROR"
        return $false
    }
}

# Function to test vCenter connection
function Test-VCenterConnection {
    param (
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        # Configure PowerCLI to handle invalid certificates
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        
        # Test connection
        Write-Log "Testing connection to $Server..." -Level "INFO"
        $connection = Connect-VIServer -Server $Server -Credential $Credential -ErrorAction Stop
        
        Write-Log "Connection successful! Connected to $Server (version: $($connection.Version))" -Level "SUCCESS"
        
        # Get some basic info to verify connection
        $vmCount = (Get-VM -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Log "Found $vmCount VMs on $Server" -Level "INFO"
        
        # Disconnect
        Disconnect-VIServer -Server $Server -Confirm:$false
        return $true
        
    } catch {
        Write-Log "Connection test to $Server failed: $_" -Level "ERROR"
        return $false
    }
}

# Function to update SSO passwords across all vCenters
function Update-SSOPasswords {
    param (
        [hashtable]$Credentials
    )
    
    Write-Host "`n--- Change SSO Password for Each vCenter ---" -ForegroundColor Cyan
    
    $Key = Get-EncryptionKey
    $UpdatedCredentials = @{}
    
    foreach ($vc in $Credentials.Keys) {
        $credential = $Credentials[$vc]
        $username = $credential.UserName
        $oldPassword = $credential.Password
        
        Write-Host "`n--- $vc ---" -ForegroundColor Cyan
        Write-Host "Stored user: $username"
        
        $newPassword = Read-Host "Enter NEW password for $username@$vc" -AsSecureString
        $newPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPassword))
        $oldPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($oldPassword))
        
        try {
            Write-Log "Connecting to $vc as $username..." "INFO"
            Connect-VIServer -Server $vc -User $username -Password $oldPlain -ErrorAction Stop | Out-Null
            
            # Perform the password update
            $split = $username.Split("@")
            $userOnly = $split[0]
            $domain = if ($split.Count -eq 2) { $split[1] } else { "vsphere.local" }
            
            Set-SsoPersonUser -User $userOnly -Domain $domain -Password $newPlain -ErrorAction Stop
            Write-Log "Updated SSO password on $vc" "SUCCESS"
            
            # Store updated credential
            $newCredential = New-Object System.Management.Automation.PSCredential($username, $newPassword)
            $UpdatedCredentials[$vc] = $newCredential
            
            Disconnect-VIServer -Confirm:$false
            
        } catch {
            Write-Log "Failed to update password on $vc : $_" "ERROR"
            # Keep original credential if failure occurs
            $UpdatedCredentials[$vc] = $credential
        }
    }
    
    return $UpdatedCredentials
}

# Main credential management function
function Invoke-VCenterCredentialManager {
    Write-Host "`n🔐 vCenter Credentials Manager v2.0" -ForegroundColor Magenta
    Write-Host "====================================" -ForegroundColor Magenta
    Write-Log "Starting vCenter credential management session" -Level "SUCCESS"
    
    # Load existing credentials
    $ExistingCreds = Get-ExistingVCenterCredentials
    
    while ($true) {
        # Display existing vCenter servers
        Write-Host "`n📊 Current vCenter Servers:" -ForegroundColor Cyan
        if ($ExistingCreds.Count -gt 0) {
            foreach ($server in $ExistingCreds.Keys) {
                Write-Host " ✅ $server (Username: $($ExistingCreds[$server].UserName))" -ForegroundColor Green
            }
        } else {
            Write-Host " ⚠️  No vCenter servers configured" -ForegroundColor Yellow
        }
        
        # Show menu options
        Write-Host "`n🛠️  Available Actions:" -ForegroundColor Cyan
        Write-Host "1. Add new vCenter server"
        Write-Host "2. Update existing vCenter server"
        Write-Host "3. Remove vCenter server"
        Write-Host "4. Test vCenter connection"
        Write-Host "5. Change SSO passwords on all vCenters"
        Write-Host "6. Show credential store info"
        Write-Host "7. Save and exit"
        Write-Host "q. Exit without saving"
        
        $choice = Read-Host "`nEnter your choice (1-7, q)"
        
        switch ($choice) {
            "1" {
                # Add new vCenter server
                Write-Host "`n➕ Add New vCenter Server" -ForegroundColor Green
                Write-Host "=========================" -ForegroundColor Green
                
                $server = Read-Host "Enter vCenter server address (FQDN or IP)"
                
                if ([string]::IsNullOrWhiteSpace($server)) {
                    Write-Host "❌ Invalid server address" -ForegroundColor Red
                    continue
                }
                
                if ($ExistingCreds.ContainsKey($server)) {
                    Write-Host "❌ Server $server already exists. Use option 2 to update it." -ForegroundColor Red
                    continue
                }
                
                $credential = Get-Credential -Message "Enter credentials for $server"
                if ($credential) {
                    $ExistingCreds[$server] = $credential
                    Write-Log "Added credentials for new server: $server" -Level "SUCCESS"
                    Write-Host "✅ Server $server added successfully" -ForegroundColor Green
                }
            }
            "2" {
                # Update existing vCenter server
                Write-Host "`n🔄 Update vCenter Server" -ForegroundColor Yellow
                Write-Host "========================" -ForegroundColor Yellow
                
                if ($ExistingCreds.Count -eq 0) {
                    Write-Host "❌ No existing vCenter servers to update!" -ForegroundColor Red
                    continue
                }
                
                Write-Host "Available servers:"
                $serverList = @($ExistingCreds.Keys)
                for ($i = 0; $i -lt $serverList.Count; $i++) {
                    Write-Host "$($i + 1). $($serverList[$i])"
                }
                Write-Host "$($serverList.Count + 1). Update all servers"
                
                $serverChoice = Read-Host "Select server to update (1-$($serverList.Count + 1))"
                
                if ($serverChoice -eq ($serverList.Count + 1).ToString()) {
                    # Update all servers
                    $sameCredentials = Read-Host "Use same credentials for all servers? (y/n)"
                    if ($sameCredentials -eq "y") {
                        $credential = Get-Credential -Message "Enter credentials for all vCenter servers"
                        if ($credential) {
                            foreach ($server in $serverList) {
                                $ExistingCreds[$server] = $credential
                                Write-Log "Updated credentials for server: $server" -Level "SUCCESS"
                            }
                            Write-Host "✅ All servers updated with same credentials" -ForegroundColor Green
                        }
                    } else {
                        foreach ($server in $serverList) {
                            $credential = Get-Credential -Message "Enter credentials for $server"
                            if ($credential) {
                                $ExistingCreds[$server] = $credential
                                Write-Log "Updated credentials for server: $server" -Level "SUCCESS"
                            }
                        }
                        Write-Host "✅ All servers updated with individual credentials" -ForegroundColor Green
                    }
                } elseif ([int]$serverChoice -ge 1 -and [int]$serverChoice -le $serverList.Count) {
                    $serverToUpdate = $serverList[[int]$serverChoice - 1]
                    $credential = Get-Credential -Message "Enter credentials for $serverToUpdate"
                    if ($credential) {
                        $ExistingCreds[$serverToUpdate] = $credential
                        Write-Log "Updated credentials for server: $serverToUpdate" -Level "SUCCESS"
                        Write-Host "✅ Server $serverToUpdate updated successfully" -ForegroundColor Green
                    }
                } else {
                    Write-Host "❌ Invalid selection" -ForegroundColor Red
                }
            }
            "3" {
                # Remove vCenter server
                Write-Host "`n🗑️ Remove vCenter Server" -ForegroundColor Red
                Write-Host "========================" -ForegroundColor Red
                
                if ($ExistingCreds.Count -eq 0) {
                    Write-Host "❌ No existing vCenter servers to remove!" -ForegroundColor Red
                    continue
                }
                
                Write-Host "Available servers:"
                $serverList = @($ExistingCreds.Keys)
                for ($i = 0; $i -lt $serverList.Count; $i++) {
                    Write-Host "$($i + 1). $($serverList[$i])"
                }
                Write-Host "$($serverList.Count + 1). Remove all servers"
                
                $serverChoice = Read-Host "Select server to remove (1-$($serverList.Count + 1))"
                
                if ($serverChoice -eq ($serverList.Count + 1).ToString()) {
                    $confirm = Read-Host "⚠️  Are you sure you want to remove ALL vCenter servers? (yes/no)"
                    if ($confirm -eq "yes") {
                        $ExistingCreds = @{}
                        Write-Log "Removed all vCenter server credentials" -Level "SUCCESS"
                        Write-Host "✅ All servers removed" -ForegroundColor Green
                    }
                } elseif ([int]$serverChoice -ge 1 -and [int]$serverChoice -le $serverList.Count) {
                    $serverToRemove = $serverList[[int]$serverChoice - 1]
                    $confirm = Read-Host "⚠️  Are you sure you want to remove $serverToRemove? (y/n)"
                    if ($confirm -eq "y") {
                        $ExistingCreds.Remove($serverToRemove)
                        Write-Log "Removed credentials for server: $serverToRemove" -Level "SUCCESS"
                        Write-Host "✅ Server $serverToRemove removed successfully" -ForegroundColor Green
                    }
                } else {
                    Write-Host "❌ Invalid selection" -ForegroundColor Red
                }
            }
            "4" {
                # Test vCenter connection
                Write-Host "`n🧪 Test vCenter Connection" -ForegroundColor Blue
                Write-Host "==========================" -ForegroundColor Blue
                
                if ($ExistingCreds.Count -eq 0) {
                    Write-Host "❌ No vCenter servers configured to test!" -ForegroundColor Red
                    continue
                }
                
                Write-Host "Available servers:"
                $serverList = @($ExistingCreds.Keys)
                for ($i = 0; $i -lt $serverList.Count; $i++) {
                    Write-Host "$($i + 1). $($serverList[$i])"
                }
                Write-Host "$($serverList.Count + 1). Test all servers"
                
                $serverChoice = Read-Host "Select server to test (1-$($serverList.Count + 1))"
                
                if ($serverChoice -eq ($serverList.Count + 1).ToString()) {
                    # Test all servers
                    foreach ($server in $serverList) {
                        Test-VCenterConnection -Server $server -Credential $ExistingCreds[$server]
                    }
                } elseif ([int]$serverChoice -ge 1 -and [int]$serverChoice -le $serverList.Count) {
                    $serverToTest = $serverList[[int]$serverChoice - 1]
                    Test-VCenterConnection -Server $serverToTest -Credential $ExistingCreds[$serverToTest]
                } else {
                    Write-Host "❌ Invalid selection" -ForegroundColor Red
                }
            }
            "5" {
                # Change SSO passwords
                if ($ExistingCreds.Count -eq 0) {
                    Write-Host "❌ No vCenter servers configured!" -ForegroundColor Red
                    continue
                }
                
                $ExistingCreds = Update-SSOPasswords -Credentials $ExistingCreds
            }
            "6" {
                # Show credential store info
                Write-Host "`n📊 Credential Store Information" -ForegroundColor Cyan
                Write-Host "===============================" -ForegroundColor Cyan
                Write-Host "Project Root: $ProjectRoot"
                Write-Host "Encryption Key: $CredentialKeyFile"
                Write-Host "Credential Store: $CredentialStore"
                Write-Host "Log File: $LogFile"
                Write-Host ""
                Write-Host "Key File Exists: $(Test-Path $CredentialKeyFile)"
                Write-Host "Credential Store Exists: $(Test-Path $CredentialStore)"
                Write-Host "Configured Servers: $($ExistingCreds.Count)"
            }
            "7" {
                # Save and exit
                if (Save-VCenterCredentials -Credentials $ExistingCreds) {
                    Write-Host "`n✅ Credentials saved successfully!" -ForegroundColor Green
                    Write-Log "Credential management session completed successfully" -Level "SUCCESS"
                } else {
                    Write-Host "`n❌ Failed to save credentials!" -ForegroundColor Red
                }
                return
            }
            "q" {
                # Exit without saving
                Write-Host "`n⚠️  Exiting without saving changes" -ForegroundColor Yellow
                Write-Log "Credential management session cancelled" -Level "WARNING"
                return
            }
            default {
                Write-Host "❌ Invalid choice. Please try again." -ForegroundColor Red
            }
        }
    }
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly
    Invoke-VCenterCredentialManager
}
