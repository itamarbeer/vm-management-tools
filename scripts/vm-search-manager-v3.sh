#!/bin/bash

# Enhanced VM Search and Management Tool v3.0 - Interactive Edition
# Complete feature parity with v2 + interactive pause functionality
# Fixes session hanging after snapshot operations

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables - now using project-relative paths
VM_CACHE_FILE="$PROJECT_ROOT/cache/vm_cache.json"
BUILD_VM_CACHE_SCRIPT="$SCRIPT_DIR/build-vm-cache.sh"
CURRENT_VM=""
CURRENT_VM_VCENTER=""
LAST_SEARCH_PATTERN=""

# Session management variables
SESSION_ACTIVE=false
SESSION_PID=""
SESSION_CMD_FILE=""
SESSION_RESP_FILE=""

# Function to print colored text
print_color() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${NC}"
}

# Check for help option
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    print_color $MAGENTA "Enhanced VM Search and Management Tool v3.0"
    print_color $MAGENTA "============================================="
    echo
    print_color $CYAN "Usage:"
    print_color $WHITE "  vmmanage                    # Interactive VM management"
    print_color $WHITE "  vmmanage --help             # Show this help"
    echo
    print_color $CYAN "Features:"
    print_color $WHITE "  • Search VMs across all vCenter servers"
    print_color $WHITE "  • Create and delete snapshots"
    print_color $WHITE "  • Power operations (on/off/restart)"
    print_color $WHITE "  • Graceful guest operations"
    print_color $WHITE "  • Detailed VM information"
    print_color $WHITE "  • Persistent PowerShell sessions for speed"
    echo
    print_color $CYAN "Setup:"
    print_color $WHITE "  vmcred                      # Setup vCenter credentials first"
    echo
    print_color $CYAN "PowerShell Commands:"
    print_color $WHITE "  pwsh -File $SCRIPT_DIR/securefile-v2.ps1           # Setup credentials"
    print_color $WHITE "  pwsh -File $SCRIPT_DIR/build-vm-cache.sh           # Build VM cache"
    echo
    exit 0
fi

# Function to check cache age
get_cache_age() {
    if [[ -f "$VM_CACHE_FILE" ]]; then
        local cache_timestamp=$(stat -c %Y "$VM_CACHE_FILE" 2>/dev/null)
        local current_timestamp=$(date +%s)
        local age_seconds=$((current_timestamp - cache_timestamp))
        local age_days=$((age_seconds / 86400))
        echo $age_days
    else
        echo 999
    fi
}

# Function to get cache info
get_cache_info() {
    if [[ -f "$VM_CACHE_FILE" ]]; then
        local age=$(get_cache_age)
        local vm_count=$(wc -l < "$VM_CACHE_FILE" 2>/dev/null || echo "0")
        echo "Cache age: $age days, VMs cached: $vm_count"
    else
        echo "No cache found"
    fi
}

# Function to build VM cache
build_vm_cache() {
    print_color $YELLOW "Building VM cache from all vCenter servers..."
    
    if "$BUILD_VM_CACHE_SCRIPT"; then
        print_color $GREEN "VM cache built successfully"
        return 0
    else
        print_color $RED "Failed to build VM cache"
        return 1
    fi
}

# Function to search VMs from cache
search_vms_from_cache() {
    local search_pattern="$1"
    local matching_vms=()
    
    if [[ ! -f "$VM_CACHE_FILE" ]]; then
        print_color $RED "VM cache not found. Building cache first..."
        if ! build_vm_cache; then
            return 1
        fi
    fi
    
    while IFS='|' read -r vm_name power_state vm_host vcenter; do
        if [[ "$vm_name" == *"$search_pattern"* ]]; then
            matching_vms+=("$vm_name|$power_state|$vm_host|$vcenter")
        fi
    done < "$VM_CACHE_FILE"
    
    if [ ${#matching_vms[@]} -eq 0 ]; then
        print_color $RED "No VMs found matching pattern: $search_pattern"
        return 1
    fi
    
    printf '%s\n' "${matching_vms[@]}"
    return 0
}

# Function to start VM session with improved communication
start_vm_session() {
    local vm_name="$1"
    local vcenter_server="$2"
    
    print_color $YELLOW "Starting persistent session for $vm_name on $vcenter_server..."
    
    # Create communication files with unique names
    SESSION_CMD_FILE="/tmp/vm_session_cmd_$$_$(date +%s)"
    SESSION_RESP_FILE="/tmp/vm_session_resp_$$_$(date +%s)"
    
    # Create the persistent PowerShell session script with improved error handling
    local session_script="/tmp/vm_session_$$.ps1"
    
    cat > "$session_script" << 'PSEOF'
param(
    [string]$VMName,
    [string]$VCenterServer,
    [string]$CommandFile,
    [string]$ResponseFile
)

# Load credentials function
function Get-VCenterCredentials {
    $CredentialKeyFile = "$env:PROJECT_ROOT/secure/credential_key.key"
    $CredentialStore = "$env:PROJECT_ROOT/secure/vcenter_credentials.enc"
    
    if (-not (Test-Path $CredentialStore)) { return $null }
    
    try {
        if (Test-Path $CredentialKeyFile) {
            $Key = Get-Content $CredentialKeyFile -ErrorAction Stop
        } else {
            return $null
        }
        
        $EncryptedData = Get-Content -Path $CredentialStore -Raw | ConvertFrom-Json
        $Credentials = @{}
        
        $EncryptedData.PSObject.Properties | ForEach-Object {
            $server = $_.Name
            $data = $_.Value
            
            try {
                $username = $data.Username
                $securePassword = $data.Password | ConvertTo-SecureString -Key ([System.Convert]::FromBase64String($Key))
                $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
                $Credentials[$server] = $credential
            } catch {
                # Skip failed credentials
            }
        }
        
        return $Credentials
    } catch {
        return $null
    }
}

# Function to write response safely
function Write-Response {
    param([string]$Message)
    try {
        $Message | Out-File -FilePath $ResponseFile -Encoding UTF8 -Force
    } catch {
        # If we can't write response, at least try to log it
        Write-Host "Response: $Message"
    }
}

# Set PowerCLI configurations
try {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null
} catch {
    Write-Response "ERROR: Failed to set PowerCLI configuration"
    exit 1
}

# Connect to vCenter
$VCenterCredentials = Get-VCenterCredentials
if (-not $VCenterCredentials -or -not $VCenterCredentials.ContainsKey($VCenterServer)) {
    Write-Response "ERROR: No credentials found for $VCenterServer"
    exit 1
}

try {
    Connect-VIServer -Server $VCenterServer -Credential $VCenterCredentials[$VCenterServer] -ErrorAction Stop | Out-Null
    Write-Response "SESSION_READY"
} catch {
    Write-Response "ERROR: Failed to connect to $VCenterServer"
    exit 1
}

# Get VM object once and cache it
try {
    $VM = Get-VM -Name $VMName -ErrorAction Stop
} catch {
    Write-Response "ERROR: VM $VMName not found"
    exit 1
}

# Main command processing loop with improved error handling
while ($true) {
    try {
        if (Test-Path $CommandFile) {
            $command = Get-Content -Path $CommandFile -Raw -ErrorAction SilentlyContinue
            if ($command) {
                $command = $command.Trim()
                Remove-Item $CommandFile -Force -ErrorAction SilentlyContinue
                
                # Clear previous response
                if (Test-Path $ResponseFile) {
                    Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
                }
                
                switch ($command) {
                    "LIST_SNAPSHOTS" {
                        try {
                            $Snapshots = Get-Snapshot -VM $VM -ErrorAction SilentlyContinue
                            if ($Snapshots.Count -eq 0) {
                                Write-Response "NO_SNAPSHOTS"
                            } else {
                                $output = @("SNAPSHOTS_START")
                                $index = 1
                                foreach ($Snap in $Snapshots) {
                                    $Age = [math]::Round(((Get-Date) - $Snap.Created).TotalDays, 1)
                                    $SizeGB = [math]::Round($Snap.SizeGB, 2)
                                    $output += "$index. $($Snap.Name)"
                                    $output += "   Created: $($Snap.Created.ToString('yyyy-MM-dd HH:mm:ss'))"
                                    $output += "   Age: $Age days"
                                    $output += "   Size: $SizeGB GB"
                                    $output += "   Description: $($Snap.Description)"
                                    $output += ""
                                    $index++
                                }
                                $output += "SNAPSHOTS_END"
                                Write-Response ($output -join "`n")
                            }
                        } catch {
                            Write-Response "ERROR: Failed to list snapshots - $($_.Exception.Message)"
                        }
                    }
                    "CREATE_SNAPSHOT" {
                        try {
                            $SnapshotName = "Manual-Snapshot-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')"
                            $NewSnapshot = New-Snapshot -VM $VM -Name $SnapshotName -Description "Manual snapshot created via Enhanced VM Search Manager v3.0"
                            Write-Response "SUCCESS: Snapshot '$SnapshotName' created successfully (Size: $([math]::Round($NewSnapshot.SizeGB, 2)) GB)"
                        } catch {
                            Write-Response "ERROR: Failed to create snapshot - $($_.Exception.Message)"
                        }
                    }
                    { $_ -like "DELETE_SNAPSHOT:*" } {
                        try {
                            $SnapName = $command.Split(':')[1]
                            $Snapshot = Get-Snapshot -VM $VM -Name $SnapName -ErrorAction SilentlyContinue
                            if ($Snapshot) {
                                # Use -RunAsync to prevent hanging and get immediate response
                                $task = Remove-Snapshot -Snapshot $Snapshot -Confirm:$false -RunAsync
                                
                                # Wait for task completion with progress
                                do {
                                    Start-Sleep -Seconds 5
                                    $task = Get-Task -Id $task.Id
                                } while ($task.State -eq "Running")
                                
                                if ($task.State -eq "Success") {
                                    Write-Response "SUCCESS: Snapshot '$SnapName' deleted successfully"
                                } else {
                                    Write-Response "ERROR: Snapshot deletion failed - $($task.Description)"
                                }
                            } else {
                                Write-Response "ERROR: Snapshot '$SnapName' not found"
                            }
                        } catch {
                            Write-Response "ERROR: Failed to delete snapshot - $($_.Exception.Message)"
                        }
                    }
                    "RESTART_VM" {
                        try {
                            Restart-VM -VM $VM -Confirm:$false | Out-Null
                            Write-Response "SUCCESS: VM restart initiated successfully"
                        } catch {
                            Write-Response "ERROR: Failed to restart VM - $($_.Exception.Message)"
                        }
                    }
                    "POWEROFF_VM" {
                        try {
                            # Refresh VM state and check current power state
                            $VM = Get-VM -Name $VMName -ErrorAction Stop
                            $currentState = $VM.PowerState
                            if ($currentState -eq "PoweredOff") {
                                Write-Response "SUCCESS: VM is already powered off"
                            } else {
                                Stop-VM -VM $VM -Confirm:$false | Out-Null
                                Write-Response "SUCCESS: VM power off initiated successfully"
                            }
                        } catch {
                            Write-Response "ERROR: Failed to power off VM - $($_.Exception.Message)"
                        }
                    }
                    "POWERON_VM" {
                        try {
                            # Refresh VM state and check current power state
                            $VM = Get-VM -Name $VMName -ErrorAction Stop
                            $currentState = $VM.PowerState
                            if ($currentState -eq "PoweredOn") {
                                Write-Response "SUCCESS: VM is already powered on"
                            } else {
                                Start-VM -VM $VM -Confirm:$false | Out-Null
                                Write-Response "SUCCESS: VM power on initiated successfully"
                            }
                        } catch {
                            Write-Response "ERROR: Failed to power on VM - $($_.Exception.Message)"
                        }
                    }
                    "GRACEFUL_SHUTDOWN" {
                        try {
                            # Check if VM is powered on and has VMware Tools
                            $VM = Get-VM -Name $VMName -ErrorAction Stop
                            if ($VM.PowerState -eq "PoweredOff") {
                                Write-Response "SUCCESS: VM is already powered off"
                            } elseif ($VM.Guest.ToolsStatus -eq "toolsNotInstalled" -or $VM.Guest.ToolsStatus -eq "toolsNotRunning") {
                                Write-Response "ERROR: VMware Tools not available - use hard power off instead"
                            } else {
                                Shutdown-VMGuest -VM $VM -Confirm:$false | Out-Null
                                Write-Response "SUCCESS: Graceful shutdown initiated - VM will shut down when guest OS completes the process"
                            }
                        } catch {
                            Write-Response "ERROR: Failed to initiate graceful shutdown - $($_.Exception.Message)"
                        }
                    }
                    "GRACEFUL_RESTART" {
                        try {
                            # Check if VM is powered on and has VMware Tools
                            $VM = Get-VM -Name $VMName -ErrorAction Stop
                            if ($VM.PowerState -eq "PoweredOff") {
                                Write-Response "ERROR: Cannot restart a powered off VM - power it on first"
                            } elseif ($VM.Guest.ToolsStatus -eq "toolsNotInstalled" -or $VM.Guest.ToolsStatus -eq "toolsNotRunning") {
                                Write-Response "ERROR: VMware Tools not available - use hard restart instead"
                            } else {
                                Restart-VMGuest -VM $VM -Confirm:$false | Out-Null
                                Write-Response "SUCCESS: Graceful restart initiated - VM will restart when guest OS completes the process"
                            }
                        } catch {
                            Write-Response "ERROR: Failed to initiate graceful restart - $($_.Exception.Message)"
                        }
                    }
                    "GET_DETAILS" {
                        try {
                            # Refresh VM object to get latest info
                            $VM = Get-VM -Name $VMName -ErrorAction Stop
                            
                            $output = @("DETAILS_START")
                            $output += "VM Details for $($VM.Name):"
                            $output += ""
                            
                            # Basic Information - all null-safe
                            $output += "Basic Information:"
                            $output += "  Name: $($VM.Name)"
                            $output += "  Power State: $($VM.PowerState)"
                            
                            # Safe access to ExtensionData
                            if ($VM.ExtensionData -and $VM.ExtensionData.OverallStatus) {
                                $output += "  Overall Status: $($VM.ExtensionData.OverallStatus)"
                            }
                            
                            $output += "  vCPUs: $($VM.NumCpu)"
                            $output += "  Memory: $($VM.MemoryGB) GB"
                            
                            if ($VM.Version) {
                                $output += "  VM Version: $($VM.Version)"
                            }
                            
                            # Safe Guest OS access
                            if ($VM.Guest -and $VM.Guest.OSFullName) {
                                $output += "  Guest OS: $($VM.Guest.OSFullName)"
                            } else {
                                $output += "  Guest OS: Not available (VM may be powered off)"
                            }
                            
                            if ($VM.Guest -and $VM.Guest.ToolsStatus) {
                                $output += "  VMware Tools: $($VM.Guest.ToolsStatus)"
                            } else {
                                $output += "  VMware Tools: Not available"
                            }
                            
                            if ($VM.Guest -and $VM.Guest.ToolsVersion) {
                                $output += "  Tools Version: $($VM.Guest.ToolsVersion)"
                            }
                            
                            if ($VM.Id) {
                                $output += "  VM ID: $($VM.Id)"
                            }
                            $output += ""
                            
                            # Infrastructure Details - all null-safe
                            $output += "Infrastructure:"
                            
                            if ($VM.VMHost) {
                                if ($VM.VMHost.Name) {
                                    $output += "  ESXi Host: $($VM.VMHost.Name)"
                                }
                                if ($VM.VMHost.Version) {
                                    $output += "  Host Version: $($VM.VMHost.Version)"
                                }
                                if ($VM.VMHost.Parent -and $VM.VMHost.Parent.Name) {
                                    $output += "  Cluster: $($VM.VMHost.Parent.Name)"
                                }
                                if ($VM.VMHost.Parent -and $VM.VMHost.Parent.Parent -and $VM.VMHost.Parent.Parent.Name) {
                                    $output += "  Datacenter: $($VM.VMHost.Parent.Parent.Name)"
                                }
                                if ($VM.VMHost.PowerState) {
                                    $output += "  Host Power State: $($VM.VMHost.PowerState)"
                                }
                            }
                            
                            if ($VM.Folder -and $VM.Folder.Name) {
                                $output += "  VM Folder: $($VM.Folder.Name)"
                            }
                            
                            if ($VM.ResourcePool -and $VM.ResourcePool.Name) {
                                $output += "  Resource Pool: $($VM.ResourcePool.Name)"
                            }
                            $output += ""
                            
                            # Snapshot Information - null-safe
                            $output += "Snapshots:"
                            try {
                                $Snapshots = Get-Snapshot -VM $VM -ErrorAction SilentlyContinue
                                if ($Snapshots -and $Snapshots.Count -gt 0) {
                                    $totalSnapshotSize = 0
                                    $output += "  Total snapshots: $($Snapshots.Count)"
                                    foreach ($snap in $Snapshots) {
                                        if ($snap -and $snap.Name) {
                                            $age = "Unknown"
                                            if ($snap.Created) {
                                                try {
                                                    $age = [math]::Round(((Get-Date) - $snap.Created).TotalDays, 1)
                                                    $age = "$age days"
                                                } catch {
                                                    $age = "Unknown"
                                                }
                                            }
                                            
                                            $snapSize = "Unknown"
                                            if ($snap.SizeGB) {
                                                try {
                                                    $totalSnapshotSize += $snap.SizeGB
                                                    $snapSize = "$([math]::Round($snap.SizeGB, 2)) GB"
                                                } catch {
                                                    $snapSize = "Unknown"
                                                }
                                            }
                                            
                                            $output += "  - $($snap.Name)"
                                            if ($snap.Created) {
                                                try {
                                                    $output += "    Created: $($snap.Created.ToString('yyyy-MM-dd HH:mm:ss'))"
                                                } catch {
                                                    # Skip if date formatting fails
                                                }
                                            }
                                            $output += "    Age: $age"
                                            $output += "    Size: $snapSize"
                                            if ($snap.Description) {
                                                $output += "    Description: $($snap.Description)"
                                            }
                                        }
                                    }
                                    if ($totalSnapshotSize -gt 0) {
                                        $output += "  Total Snapshot Size: $([math]::Round($totalSnapshotSize, 2)) GB"
                                    }
                                } else {
                                    $output += "  No snapshots found"
                                }
                            } catch {
                                $output += "  Unable to retrieve snapshot information"
                            }
                            
                            $output += "DETAILS_END"
                            Write-Response ($output -join "`n")
                            
                        } catch {
                            Write-Response "ERROR: Failed to get VM details - $($_.Exception.Message)"
                        }
                    }
                    "END_SESSION" {
                        try {
                            Disconnect-VIServer -Server $VCenterServer -Confirm:$false
                            Write-Response "SESSION_ENDED"
                        } catch {
                            Write-Response "SESSION_ENDED"
                        }
                        break
                    }
                    default {
                        Write-Response "ERROR: Unknown command: $command"
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 100  # Much faster polling - check every 100ms
    } catch {
        Write-Response "ERROR: Session error - $($_.Exception.Message)"
        break
    }
}
PSEOF

    # Start the PowerShell session in background
    export PROJECT_ROOT="$PROJECT_ROOT"
    pwsh -File "$session_script" -VMName "$vm_name" -VCenterServer "$vcenter_server" -CommandFile "$SESSION_CMD_FILE" -ResponseFile "$SESSION_RESP_FILE" &
    SESSION_PID=$!
    
    # Wait for session to be ready
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if [[ -f "$SESSION_RESP_FILE" ]]; then
            local status=$(cat "$SESSION_RESP_FILE" 2>/dev/null)
            if [[ "$status" == "SESSION_READY" ]]; then
                SESSION_ACTIVE=true
                rm -f "$SESSION_RESP_FILE"
                print_color $GREEN "Persistent session established - instant operations ready!"
                return 0
            elif [[ "$status" == ERROR:* ]]; then
                print_color $RED "Session failed: ${status#ERROR: }"
                cleanup_session
                return 1
            fi
        fi
        sleep 1
        ((wait_count++))
    done
    
    print_color $RED "Session startup timeout"
    cleanup_session
    return 1
}

# Improved function to send command to session with stdin protection
send_session_command() {
    local command="$1"
    local timeout_seconds="${2:-15}"  # Reduced default timeout
    
    if [[ "$SESSION_ACTIVE" != true ]]; then
        print_color $RED "No active session"
        return 1
    fi
    
    # Check if session is still alive
    if ! kill -0 "$SESSION_PID" 2>/dev/null; then
        print_color $RED "Session died unexpectedly"
        SESSION_ACTIVE=false
        return 1
    fi
    
    # Clear any existing response file first
    rm -f "$SESSION_RESP_FILE" 2>/dev/null
    
    # Send command
    echo "$command" > "$SESSION_CMD_FILE"
    
    # Wait for response with faster polling
    local wait_count=0
    local response=""
    
    while [[ $wait_count -lt $((timeout_seconds * 2)) ]]; do  # Double iterations with 0.5s sleep
        if [[ -f "$SESSION_RESP_FILE" ]]; then
            response=$(cat "$SESSION_RESP_FILE" 2>/dev/null)
            if [[ -n "$response" ]]; then
                rm -f "$SESSION_RESP_FILE"
                echo "$response"
                
                # Reset terminal state after session command
                stty sane 2>/dev/null || true
                return 0
            fi
        fi
        
        # Check if session is still alive during wait
        if ! kill -0 "$SESSION_PID" 2>/dev/null; then
            print_color $RED "Session died during operation"
            SESSION_ACTIVE=false
            return 1
        fi
        
        sleep 0.5  # Faster polling - check every 0.5 seconds instead of 1 second
        ((wait_count++))
    done
    
    print_color $RED "Command timeout after ${timeout_seconds}s"
    return 1
}

# Function to cleanup session
cleanup_session() {
    if [[ "$SESSION_ACTIVE" == true ]]; then
        print_color $YELLOW "Ending VM session..."
        
        # Send end session command
        if [[ -n "$SESSION_CMD_FILE" ]] && [[ -f "$SESSION_CMD_FILE" ]]; then
            echo "END_SESSION" > "$SESSION_CMD_FILE" 2>/dev/null || true
            sleep 2
        fi
        
        # Kill session if still running
        if [[ -n "$SESSION_PID" ]] && kill -0 "$SESSION_PID" 2>/dev/null; then
            kill "$SESSION_PID" 2>/dev/null || true
            sleep 1
            # Force kill if still running
            if kill -0 "$SESSION_PID" 2>/dev/null; then
                kill -9 "$SESSION_PID" 2>/dev/null || true
            fi
        fi
        
        # Cleanup files
        rm -f "$SESSION_CMD_FILE" "$SESSION_RESP_FILE" /tmp/vm_session_$$.ps1 2>/dev/null || true
        
        SESSION_ACTIVE=false
        SESSION_PID=""
        SESSION_CMD_FILE=""
        SESSION_RESP_FILE=""
    fi
}

# Function to display VM selection menu
show_vm_selection_menu() {
    local vm_data="$1"
    local vm_list=()
    local index=1
    
    while true; do
        clear
        print_color $MAGENTA "Enhanced VM Search and Management Tool v3.0"
        print_color $MAGENTA "=================================================="
        echo
        print_color $CYAN "Found VMs matching your search:"
        echo
        printf "%-3s | %-30s | %-12s | %-20s | %s\n" "#" "VM Name" "Power State" "Host" "vCenter"
        printf "%-3s-+-%-30s-+-%-12s-+-%-20s-+-%s\n" "---" "------------------------------" "------------" "--------------------" "----------------"
        
        # Reset arrays
        vm_list=()
        index=1
        
        # Parse VM data
        while IFS='|' read -r vm_name power_state vm_host vcenter; do
            if [[ -n "$vm_name" ]]; then
                printf "%-3s | %-30s | %-12s | %-20s | %s\n" "$index" "$vm_name" "$power_state" "$vm_host" "$vcenter"
                vm_list+=("$vm_name|$power_state|$vm_host|$vcenter")
                ((index++))
            fi
        done <<< "$vm_data"
        
        echo
        print_color $CYAN "Options:"
        echo "1-$((index-1)). Select a VM to manage"
        echo "r. Refresh VM list"
        echo "s. New search"
        echo "q. Quit"
        echo
        
        read -p "Choice: " choice
        
        case "$choice" in
            r|R)
                print_color $YELLOW "Refreshing VM cache..."
                if build_vm_cache; then
                    if [[ -n "$LAST_SEARCH_PATTERN" ]]; then
                        vm_data=$(search_vms_from_cache "$LAST_SEARCH_PATTERN")
                    fi
                fi
                continue
                ;;
            s|S)
                return 0
                ;;
            q|Q)
                script_exit
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#vm_list[@]}" ]; then
                    local selected_vm_info="${vm_list[$((choice-1))]}"
                    IFS='|' read -r CURRENT_VM power_state vm_host CURRENT_VM_VCENTER <<< "$selected_vm_info"
                    
                    print_color $GREEN "Selected VM: $CURRENT_VM on $CURRENT_VM_VCENTER"
                    
                    # Start persistent session for this VM
                    if start_vm_session "$CURRENT_VM" "$CURRENT_VM_VCENTER"; then
                        show_vm_management_menu
                        cleanup_session
                    else
                        print_color $RED "Failed to establish session"
                        sleep 3  # Brief pause to read the error
                    fi
                else
                    print_color $RED "Invalid choice"
                    sleep 2
                fi
                ;;
        esac
    done
}

# Function to show VM management menu with improved error handling and interactive pauses
show_vm_management_menu() {
    while true; do
        clear
        print_color $MAGENTA "VM Management: $CURRENT_VM (Session Active)"
        print_color $MAGENTA "=================================================="
        echo
        print_color $CYAN "VM Information:"
        echo "Name: $CURRENT_VM"
        echo "vCenter: $CURRENT_VM_VCENTER"
        print_color $GREEN "Status: Connected - Instant operations ready!"
        echo
        print_color $CYAN "Available Actions:"
        echo "1. Restart VM (Hard)"
        echo "2. Create Snapshot"
        echo "3. List Snapshots"
        echo "4. Delete Snapshot"
        echo "5. Power Off VM (Hard)"
        echo "6. Power On VM"
        echo "7. VM Details"
        echo "8. Graceful Shutdown (Guest)"
        echo "9. Graceful Restart (Guest)"
        echo
        echo "b. Back to VM list (ends session)"
        echo "q. Quit"
        echo
        
        read -p "Choice: " action_choice
        
        # Clear any trailing input and handle empty input
        if [[ -z "$action_choice" ]]; then
            # Flush any pending input
            while read -t 0.1 -n 1; do :; done 2>/dev/null
            continue  # Skip empty input and redraw menu
        fi
        
        case "$action_choice" in
            1)
                print_color $YELLOW "Restarting VM..."
                local result=$(send_session_command "RESTART_VM")
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2  # Brief pause to read the result
                ;;
            2)
                print_color $YELLOW "Sending snapshot creation command..."
                print_color $CYAN "Snapshot creation may take a few minutes"
                
                local result=$(send_session_command "CREATE_SNAPSHOT" 300)
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                    print_color $GREEN "Snapshot creation completed!"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2  # Brief pause to read the result
                ;;
            3)
                clear
                print_color $MAGENTA "Snapshot List: $CURRENT_VM (Instant)"
                print_color $MAGENTA "=========================================="
                echo
                
                local result=$(send_session_command "LIST_SNAPSHOTS")
                if [[ "$result" == "NO_SNAPSHOTS" ]]; then
                    print_color $CYAN "No snapshots found for this VM"
                elif [[ "$result" == SNAPSHOTS_START* ]]; then
                    echo "$result" | sed '/^SNAPSHOTS_START$/d; /^SNAPSHOTS_END$/d' | while IFS= read -r line; do
                        if [[ "$line" =~ ^[0-9]+\. ]]; then
                            print_color $WHITE "$line"
                        else
                            echo "   $line"
                        fi
                    done
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                # Interactive pause for snapshot list
                read -p "Press Enter to continue..."
                ;;
            4)
                clear
                print_color $MAGENTA "Delete Snapshot: $CURRENT_VM (Instant)"
                print_color $MAGENTA "==========================================="
                echo
                
                # First show current snapshots
                print_color $YELLOW "Getting current snapshots..."
                local result=$(send_session_command "LIST_SNAPSHOTS")
                if [[ "$result" == "NO_SNAPSHOTS" ]]; then
                    print_color $CYAN "No snapshots found for this VM"
                elif [[ "$result" == SNAPSHOTS_START* ]]; then
                    echo "$result" | sed '/^SNAPSHOTS_START$/d; /^SNAPSHOTS_END$/d' | while IFS= read -r line; do
                        if [[ "$line" =~ ^[0-9]+\. ]]; then
                            print_color $WHITE "$line"
                        else
                            echo "   $line"
                        fi
                    done
                    echo
                    print_color $YELLOW "Enter the exact snapshot name to delete:"
                    read -p "Snapshot name: " snap_name
                    
                    if [[ -n "$snap_name" ]]; then
                        print_color $RED "Are you sure you want to delete snapshot '$snap_name'? (y/N)"
                        read -p "Confirm: " confirm
                        
                        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                            print_color $YELLOW "Sending delete command..."
                            print_color $CYAN "Large snapshots may take several minutes to delete"
                            print_color $CYAN "   Please wait while the operation completes..."
                            
                            # Use longer timeout for snapshot deletion
                            local delete_result=$(send_session_command "DELETE_SNAPSHOT:$snap_name" 600)
                            if [[ "$delete_result" == SUCCESS:* ]]; then
                                print_color $GREEN "${delete_result#SUCCESS: }"
                                print_color $GREEN "Snapshot deletion completed!"
                            elif [[ "$delete_result" == ERROR:* ]]; then
                                print_color $RED "${delete_result#ERROR: }"
                            else
                                print_color $RED "Unexpected response: $delete_result"
                            fi
                        else
                            print_color $YELLOW "Cancelled"
                        fi
                    fi
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2  # Brief pause to read the result
                ;;
            5)
                print_color $YELLOW "Powering off VM..."
                local result=$(send_session_command "POWEROFF_VM")
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2  # Brief pause to read the result
                ;;
            6)
                print_color $YELLOW "Powering on VM..."
                local result=$(send_session_command "POWERON_VM")
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2  # Brief pause to read the result
                ;;
            7)
                clear
                print_color $MAGENTA "VM Details: $CURRENT_VM (Instant)"
                print_color $MAGENTA "====================================="
                echo
                
                print_color $YELLOW "Getting comprehensive VM details..."
                local result=$(send_session_command "GET_DETAILS" 30)
                if [[ "$result" == DETAILS_START* ]]; then
                    echo "$result" | sed '/^DETAILS_START$/d; /^DETAILS_END$/d'
                    echo
                    print_color $GREEN "VM details retrieved successfully"
                    echo
                    print_color $CYAN "Review the detailed information above"
                    echo
                    # Interactive pause for VM details
                    read -p "Press Enter to continue..."
                else
                    print_color $RED "${result#ERROR: }"
                    sleep 2
                fi
                ;;
            8)
                print_color $YELLOW "Graceful shutdown (asking guest OS)..."
                print_color $CYAN "This will ask the guest OS to shut down properly"
                local result=$(send_session_command "GRACEFUL_SHUTDOWN")
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2
                ;;
            9)
                print_color $YELLOW "Graceful restart (asking guest OS)..."
                print_color $CYAN "This will ask the guest OS to restart properly"
                local result=$(send_session_command "GRACEFUL_RESTART")
                if [[ "$result" == SUCCESS:* ]]; then
                    print_color $GREEN "${result#SUCCESS: }"
                else
                    print_color $RED "${result#ERROR: }"
                fi
                echo
                sleep 2
                ;;
            b|B)
                return 0
                ;;
            q|Q)
                cleanup_session
                script_exit
                ;;
            *)
                print_color $RED "Invalid choice"
                sleep 2
                ;;
        esac
    done
}

# Function to clean exit
script_exit() {
    cleanup_session
    print_color $YELLOW "Goodbye!"
    print_color $YELLOW "Cleaning up temporary files..."
    rm -f /tmp/vm_session_* /tmp/vm_*_$$ 2>/dev/null
    print_color $GREEN "Cleanup completed"
    exit 0
}

# Main execution function
main() {
    print_color $MAGENTA "Enhanced VM Search and Management Tool v3.0"
    print_color $MAGENTA "=================================================="
    echo
    
    # Check cache status
    local cache_age=$(get_cache_age)
    if [[ $cache_age -lt 7 ]]; then
        print_color $GREEN "Using fresh VM cache ($cache_age days old)"
    else
        print_color $YELLOW "VM cache is $cache_age days old, consider refreshing"
    fi
    
    local cache_info=$(get_cache_info)
    print_color $CYAN "Cache info: $cache_info"
    
    # Main search loop
    while true; do
        clear
        print_color $MAGENTA "Enhanced VM Search and Management Tool v3.0"
        print_color $MAGENTA "=================================================="
        echo
        
        print_color $CYAN "VM Search"
        echo
        
        read -p "Enter VM search pattern (or 'q' to quit): " search_pattern
        
        case "$search_pattern" in
            q|Q)
                script_exit
                ;;
            "")
                print_color $RED "Please enter a search pattern"
                sleep 2
                continue
                ;;
            *)
                LAST_SEARCH_PATTERN="$search_pattern"
                
                # Search VMs from cache
                if vm_data=$(search_vms_from_cache "$search_pattern"); then
                    show_vm_selection_menu "$vm_data"
                else
                    print_color $RED "No VMs found or search failed"
                    sleep 2
                fi
                ;;
        esac
    done
}

# Set up cleanup trap
trap cleanup_session EXIT

# Run main function
main "$@"
