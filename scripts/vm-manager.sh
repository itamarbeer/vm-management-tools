#!/bin/bash

# VM Manager - quick VM search and operations
# Works with cached VM data from multiple vCenters

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_FILE="$PROJECT_ROOT/vm_cache_simple.txt"
CRED_STORE="$PROJECT_ROOT/secure/vcenter_credentials.enc"
CRED_KEY="$PROJECT_ROOT/secure/credential_key.key"

CURRENT_VM=""
CURRENT_VCENTER=""
LAST_SEARCH=""

# Session vars
SESSION_ACTIVE=false
SESSION_PID=""
CMD_FILE=""
RESP_FILE=""

msg() {
    echo -e "${1}${2}${NC}"
}

# Basic checks
check_prereqs() {
    if ! command -v pwsh >/dev/null 2>&1; then
        msg $RED "Need PowerShell - install with: sudo snap install powershell --classic"
        exit 1
    fi
    
    if [[ ! -f "$CRED_STORE" ]] || [[ ! -f "$CRED_KEY" ]]; then
        msg $RED "Missing credential files - run setup first"
        exit 1
    fi
}

# Cache age in days
cache_age() {
    if [[ -f "$CACHE_FILE" ]]; then
        local age=$(( ($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0")) / 86400 ))
        echo $age
    else
        echo 999
    fi
}

# Build cache if needed
maybe_build_cache() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        msg $YELLOW "No cache - building..."
        pwsh -File "$PROJECT_ROOT/scripts/build-vm-cache-v2.ps1"
    fi
}

# Search VMs
search_vms() {
    local pattern="$1"
    maybe_build_cache
    
    if [[ ! -f "$CACHE_FILE" ]]; then
        msg $RED "No cache available"
        return 1
    fi
    
    grep -i "$pattern" "$CACHE_FILE" || {
        msg $RED "No VMs found matching: $pattern"
        return 1
    }
}

# Start PowerShell session for VM ops
start_session() {
    local vm="$1"
    local vc="$2"
    
    msg $YELLOW "Starting session for $vm..."
    
    CMD_FILE="/tmp/vm_cmd_$$"
    RESP_FILE="/tmp/vm_resp_$$"
    
    # Simple PowerShell session
    cat > "/tmp/session_$$.ps1" << 'EOF'
param($VM, $VC, $CmdFile, $RespFile)

# Load creds
$key = Get-Content "$ProjectRoot/secure/credential_key.key"
$creds = Get-Content "$ProjectRoot/secure/vcenter_credentials.enc" -Raw | ConvertFrom-Json

$username = $creds.$VC.Username
$password = $creds.$VC.Password | ConvertTo-SecureString -Key ([Convert]::FromBase64String($key))
$cred = New-Object PSCredential($username, $password)

# Connect
Import-Module VMware.PowerCLI -Force
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

try {
    Connect-VIServer -Server $VC -Credential $cred | Out-Null
    $vmObj = Get-VM -Name $VM
    "READY" | Out-File $RespFile
} catch {
    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
    exit
}

# Command loop
while ($true) {
    if (Test-Path $CmdFile) {
        $cmd = Get-Content $CmdFile
        Remove-Item $CmdFile -Force
        
        switch ($cmd) {
            "snapshots" {
                $snaps = Get-Snapshot -VM $vmObj
                if ($snaps) {
                    $output = "SNAPSHOTS`n"
                    $snaps | ForEach-Object { 
                        $age = [math]::Round(((Get-Date) - $_.Created).TotalDays, 1)
                        $output += "$($_.Name) - $($_.Created) ($age days, $([math]::Round($_.SizeGB,1)) GB)`n"
                    }
                    $output | Out-File $RespFile
                } else {
                    "NO_SNAPSHOTS" | Out-File $RespFile
                }
            }
            "create_snap" {
                try {
                    $name = "$env:HOSTNAME@$env:USER $(Get-Date -Format 'yyyy:MM:dd')"
                    $snap = New-Snapshot -VM $vmObj -Name $name -Description "Created by $env:USER"
                    "SUCCESS: Created $name" | Out-File $RespFile
                } catch {
                    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
                }
            }
            { $_ -like "delete_snap:*" } {
                $snapName = $cmd.Split(':')[1]
                try {
                    $snap = Get-Snapshot -VM $vmObj -Name $snapName
                    Remove-Snapshot -Snapshot $snap -Confirm:$false
                    "SUCCESS: Deleted $snapName" | Out-File $RespFile
                } catch {
                    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
                }
            }
            "restart" {
                try {
                    Restart-VM -VM $vmObj -Confirm:$false
                    "SUCCESS: Restart initiated" | Out-File $RespFile
                } catch {
                    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
                }
            }
            "poweroff" {
                try {
                    Stop-VM -VM $vmObj -Confirm:$false
                    "SUCCESS: Power off initiated" | Out-File $RespFile
                } catch {
                    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
                }
            }
            "poweron" {
                try {
                    Start-VM -VM $vmObj -Confirm:$false
                    "SUCCESS: Power on initiated" | Out-File $RespFile
                } catch {
                    "ERROR: $($_.Exception.Message)" | Out-File $RespFile
                }
            }
            "details" {
                $info = "VM: $($vmObj.Name)`n"
                $info += "Power: $($vmObj.PowerState)`n"
                $info += "CPU: $($vmObj.NumCpu)`n"
                $info += "RAM: $($vmObj.MemoryGB) GB`n"
                $info += "OS: $($vmObj.Guest.OSFullName)`n"
                $info | Out-File $RespFile
            }
            "quit" {
                Disconnect-VIServer -Confirm:$false
                break
            }
        }
    }
    Start-Sleep -Milliseconds 200
}
EOF

    pwsh -File "/tmp/session_$$.ps1" -VM "$vm" -VC "$vc" -CmdFile "$CMD_FILE" -RespFile "$RESP_FILE" &
    SESSION_PID=$!
    
    # Wait for ready
    local count=0
    while [[ $count -lt 20 ]]; do
        if [[ -f "$RESP_FILE" ]]; then
            local status=$(cat "$RESP_FILE")
            if [[ "$status" == "READY" ]]; then
                SESSION_ACTIVE=true
                rm -f "$RESP_FILE"
                msg $GREEN "Session ready"
                return 0
            elif [[ "$status" == ERROR:* ]]; then
                msg $RED "${status#ERROR: }"
                return 1
            fi
        fi
        sleep 1
        ((count++))
    done
    
    msg $RED "Session timeout"
    return 1
}

# Send command and get response
send_cmd() {
    local cmd="$1"
    
    if [[ "$SESSION_ACTIVE" != true ]]; then
        msg $RED "No session"
        return 1
    fi
    
    echo "$cmd" > "$CMD_FILE"
    
    # Wait for response
    local count=0
    while [[ $count -lt 30 ]]; do
        if [[ -f "$RESP_FILE" ]]; then
            cat "$RESP_FILE"
            rm -f "$RESP_FILE"
            return 0
        fi
        sleep 0.5
        ((count++))
    done
    
    msg $RED "Command timeout"
    return 1
}

# Cleanup
cleanup() {
    if [[ "$SESSION_ACTIVE" == true ]]; then
        echo "quit" > "$CMD_FILE" 2>/dev/null || true
        sleep 1
        kill "$SESSION_PID" 2>/dev/null || true
        rm -f "$CMD_FILE" "$RESP_FILE" "/tmp/session_$$.ps1" 2>/dev/null || true
        SESSION_ACTIVE=false
    fi
}

# VM selection menu
vm_menu() {
    local vms="$1"
    local vm_list=()
    local i=1
    
    while true; do
        clear
        msg $CYAN "=== VM Search Results ==="
        echo
        
        # Reset list
        vm_list=()
        i=1
        
        while IFS='|' read -r name state host vc; do
            if [[ -n "$name" ]]; then
                printf "%2d. %-25s %-12s %-15s %s\n" "$i" "$name" "$state" "$host" "$vc"
                vm_list+=("$name|$state|$host|$vc")
                ((i++))
            fi
        done <<< "$vms"
        
        echo
        echo "r. Refresh cache"
        echo "s. New search"
        echo "q. Quit"
        echo
        read -p "Select VM (1-$((i-1))): " choice
        
        case "$choice" in
            r)
                msg $YELLOW "Refreshing cache..."
                pwsh -File "$PROJECT_ROOT/scripts/build-vm-cache-v2.ps1"
                if [[ -n "$LAST_SEARCH" ]]; then
                    vms=$(search_vms "$LAST_SEARCH")
                fi
                ;;
            s)
                return 0
                ;;
            q)
                exit 0
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#vm_list[@]}" ]]; then
                    local selected="${vm_list[$((choice-1))]}"
                    IFS='|' read -r CURRENT_VM state host CURRENT_VCENTER <<< "$selected"
                    
                    msg $GREEN "Selected: $CURRENT_VM on $CURRENT_VCENTER"
                    
                    if start_session "$CURRENT_VM" "$CURRENT_VCENTER"; then
                        vm_ops_menu
                        cleanup
                    else
                        msg $RED "Failed to start session"
                        read -p "Press Enter..."
                    fi
                else
                    msg $RED "Invalid choice"
                    sleep 1
                fi
                ;;
        esac
    done
}

# VM operations menu
vm_ops_menu() {
    while true; do
        clear
        msg $CYAN "=== VM Operations: $CURRENT_VM ==="
        echo
        msg $GREEN "Session active - operations are fast"
        echo
        echo "1. List snapshots"
        echo "2. Create snapshot"
        echo "3. Delete snapshot"
        echo "4. Restart VM"
        echo "5. Power off VM"
        echo "6. Power on VM"
        echo "7. VM details"
        echo
        echo "b. Back"
        echo "q. Quit"
        echo
        read -p "Choice: " choice
        
        case "$choice" in
            1)
                clear
                msg $CYAN "Snapshots for $CURRENT_VM:"
                echo
                local result=$(send_cmd "snapshots")
                if [[ "$result" == "NO_SNAPSHOTS" ]]; then
                    msg $YELLOW "No snapshots"
                else
                    echo "$result" | sed '/^SNAPSHOTS$/d'
                fi
                echo
                read -p "Press Enter..."
                ;;
            2)
                msg $YELLOW "Creating snapshot..."
                local result=$(send_cmd "create_snap")
                if [[ "$result" == SUCCESS:* ]]; then
                    msg $GREEN "${result#SUCCESS: }"
                else
                    msg $RED "${result#ERROR: }"
                fi
                read -p "Press Enter..."
                ;;
            3)
                clear
                msg $CYAN "Current snapshots:"
                local snaps=$(send_cmd "snapshots")
                if [[ "$snaps" == "NO_SNAPSHOTS" ]]; then
                    msg $YELLOW "No snapshots to delete"
                    read -p "Press Enter..."
                    continue
                fi
                echo "$snaps" | sed '/^SNAPSHOTS$/d'
                echo
                read -p "Enter snapshot name to delete: " snap_name
                if [[ -n "$snap_name" ]]; then
                    read -p "Delete '$snap_name'? (y/N): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        msg $YELLOW "Deleting snapshot..."
                        local result=$(send_cmd "delete_snap:$snap_name")
                        if [[ "$result" == SUCCESS:* ]]; then
                            msg $GREEN "${result#SUCCESS: }"
                        else
                            msg $RED "${result#ERROR: }"
                        fi
                    fi
                fi
                read -p "Press Enter..."
                ;;
            4)
                read -p "Restart $CURRENT_VM? (y/N): " confirm
                if [[ "$confirm" == "y" ]]; then
                    local result=$(send_cmd "restart")
                    if [[ "$result" == SUCCESS:* ]]; then
                        msg $GREEN "${result#SUCCESS: }"
                    else
                        msg $RED "${result#ERROR: }"
                    fi
                fi
                read -p "Press Enter..."
                ;;
            5)
                read -p "Power off $CURRENT_VM? (y/N): " confirm
                if [[ "$confirm" == "y" ]]; then
                    local result=$(send_cmd "poweroff")
                    if [[ "$result" == SUCCESS:* ]]; then
                        msg $GREEN "${result#SUCCESS: }"
                    else
                        msg $RED "${result#ERROR: }"
                    fi
                fi
                read -p "Press Enter..."
                ;;
            6)
                local result=$(send_cmd "poweron")
                if [[ "$result" == SUCCESS:* ]]; then
                    msg $GREEN "${result#SUCCESS: }"
                else
                    msg $RED "${result#ERROR: }"
                fi
                read -p "Press Enter..."
                ;;
            7)
                clear
                msg $CYAN "VM Details:"
                echo
                send_cmd "details"
                echo
                read -p "Press Enter..."
                ;;
            b)
                return 0
                ;;
            q)
                cleanup
                exit 0
                ;;
            *)
                msg $RED "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Main loop
main() {
    check_prereqs
    
    while true; do
        clear
        msg $CYAN "=== VM Manager ==="
        echo
        msg $YELLOW "User: $USER on $HOSTNAME"
        local age=$(cache_age)
        if [[ $age -lt 7 ]]; then
            msg $GREEN "Cache: $age days old"
        else
            msg $YELLOW "Cache: $age days old (consider refresh)"
        fi
        echo
        
        read -p "Search VMs (or 'q' to quit): " pattern
        
        case "$pattern" in
            q|Q)
                exit 0
                ;;
            "")
                msg $RED "Enter search pattern"
                sleep 1
                ;;
            *)
                LAST_SEARCH="$pattern"
                if vms=$(search_vms "$pattern"); then
                    vm_menu "$vms"
                else
                    read -p "Press Enter..."
                fi
                ;;
        esac
    done
}

trap cleanup EXIT
main "$@"
