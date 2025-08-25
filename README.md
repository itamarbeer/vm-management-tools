# VM Management Tools

VMware vCenter management toolkit for Ubuntu environments. Provides interactive VM search, credential management, and automated cache building.

## Quick Start

### Complete Setup
```bash
curl -sSL https://raw.githubusercontent.com/itamarbeer/vm-management-tools/main/scripts/full-setup.sh | bash
```

### Manual Installation
```bash
git clone https://github.com/itamarbeer/vm-management-tools.git
cd vm-management-tools
./scripts/full-setup.sh
```

## How to Use

### 1. Initial Setup

After installation, add the commands to your shell:
```bash
# Add to your ~/.bashrc
alias vmmanage='~/vm-management-tools/scripts/vm-search-manager-v3.sh'
alias vmcred='pwsh -File ~/vm-management-tools/scripts/securefile-v2.ps1'

# Reload your shell
source ~/.bashrc
```

### 2. Configure vCenter Credentials

Set up your vCenter server credentials (required first step):
```bash
vmcred
```

This will:
- Prompt for vCenter server addresses
- Securely encrypt and store your credentials
- Create the credential files needed for VM operations

### 3. VM Search and Management

Launch the interactive VM manager:
```bash
vmmanage
```

**Features Available:**
- **Search VMs** - Find VMs by name across all vCenters
- **VM Details** - View comprehensive VM information
- **Snapshot Management** - Create and delete VM snapshots
- **Power Operations** - Start, stop, restart VMs (hard and graceful)
- **Real-time Operations** - Persistent PowerShell sessions for instant responses

**Example Session:**
```
Enhanced VM Search and Management Tool v3.0
===========================================

Enter VM search pattern (or 'q' to quit): web-server

Found VMs matching your search:

#   | VM Name              | Power State  | Host                 | vCenter
----+----------------------+--------------+----------------------+----------------
1   | web-server-01        | PoweredOn    | esxi-host-01        | vcenter1.local
2   | web-server-02        | PoweredOff   | esxi-host-02        | vcenter1.local

Select a VM to manage: 1

VM Management: web-server-01 (Session Active)
==============================================

Available Actions:
1. Restart VM (Hard)
2. Create Snapshot
3. List Snapshots
4. Delete Snapshot
5. Power Off VM (Hard)
6. Power On VM
7. VM Details
8. Graceful Shutdown (Guest)
9. Graceful Restart (Guest)
```

### 4. Build VM Cache (Automatic)

The VM cache is built automatically when needed, but you can also:

**Manual cache build:**
```bash
cd ~/vm-management-tools
./scripts/build-vm-cache.sh
```

**Schedule automatic updates (optional):**
```bash
# Add to crontab for updates every 6 hours
crontab -e
# Add line: 0 */6 * * * ~/vm-management-tools/scripts/build-vm-cache.sh >/dev/null 2>&1
```

### 5. Quick Commands

**Get help:**
```bash
vmmanage --help
```

**Validate project:**
```bash
cd ~/vm-management-tools
./scripts/validate-project.sh
```

**Direct PowerShell commands:**
```bash
# Setup credentials
pwsh -File ~/vm-management-tools/scripts/securefile-v2.ps1

# Build VM cache  
pwsh -File ~/vm-management-tools/scripts/build-vm-cache-v2.ps1
```

## Usage Examples

### Find and Manage a VM
```bash
vmmanage
# Enter search pattern: "database"
# Select VM from results
# Choose action: Create snapshot, restart, etc.
```

### Setup New vCenter
```bash
vmcred
# Follow prompts to add vCenter server and credentials
```

### Get Help
```bash
vmmanage --help
# Shows all available features and commands
```

### Quick VM Details
```bash
vmmanage
# Search for VM
# Select VM
# Choose option 7 for detailed information
```

## Project Structure

```
scripts/
├── full-setup.sh              # Main installation script
├── vm-search-manager-v3.sh    # Interactive VM manager
├── securefile-v2.ps1          # Credential management
├── build-vm-cache-v2.ps1      # VM cache builder
├── setup-environment.ps1      # PowerShell environment setup
└── vm-manager.sh              # Additional VM utilities
```

## Requirements

- Ubuntu 20.04+ or WSL2
- sudo access for package installation
- Internet connection for PowerCLI download

## Features

- Interactive VM search and management
- Secure credential storage
- Multiple vCenter support
- VM cache for faster searches
- WSL2 compatible
- PowerCLI integration

## Troubleshooting

### PowerCLI Issues
If PowerCLI installation fails:
```bash
# Try Windows PowerShell (if in WSL)
powershell.exe -Command "Install-Module VMware.PowerCLI -Scope CurrentUser -Force"

# Or use the installer script
~/vm-management-tools/install-powercli
```

### VM Search Returns No Results
1. **Check credentials:** `vmcred`
2. **Rebuild cache:** `cd ~/vm-management-tools && ./scripts/build-vm-cache.sh`
3. **Validate project:** `cd ~/vm-management-tools && ./scripts/validate-project.sh`

### Connection Problems
- Verify vCenter server addresses in credentials
- Test network connectivity: `ping your-vcenter-server`
- Ensure credentials have VM management permissions
- Check vCenter certificate trust

### Permission Errors
```bash
# Fix secure directory permissions
chmod 700 ~/vm-management-tools/secure
```

### Command Not Found
```bash
# Add aliases to bashrc
echo 'alias vmmanage="~/vm-management-tools/scripts/vm-search-manager-v3.sh"' >> ~/.bashrc
echo 'alias vmcred="pwsh -File ~/vm-management-tools/scripts/securefile-v2.ps1"' >> ~/.bashrc
source ~/.bashrc
```

## License

MIT License - see LICENSE file for details.
