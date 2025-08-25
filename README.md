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

### 1. Initial Configuration

After installation, configure your vCenter credentials:
```bash
~/vm-credentials
```

This will prompt you to:
- Add vCenter server addresses
- Enter username and password for each vCenter
- Credentials are encrypted and stored securely

### 2. Build VM Cache

Build a searchable cache of all VMs across your vCenters:
```bash
cd ~/vm-management-tools
pwsh -File scripts/build-vm-cache-v2.ps1
```

This process:
- Connects to all configured vCenters
- Retrieves VM information (name, IP, host, status)
- Creates a local cache for fast searching
- Should be run periodically to keep data current

### 3. VM Search and Management

Launch the interactive VM manager:
```bash
~/vm-manager
```

**Available Options:**
- **Search by VM Name** - Find VMs by partial or full name
- **Search by IP Address** - Locate VMs by IP address
- **List All VMs** - Display all cached VMs
- **VM Details** - Show detailed information for specific VMs
- **Refresh Cache** - Update VM information from vCenters

**Example Search Session:**
```
VM Management Tools v3.0
========================

1. Search by VM Name
2. Search by IP Address  
3. List All VMs
4. Refresh Cache
5. Exit

Select option: 1
Enter VM name (partial match): web-server

Found 3 matching VMs:
- web-server-01 (192.168.1.10) on vcenter1.company.com
- web-server-02 (192.168.1.11) on vcenter1.company.com  
- web-server-prod (10.0.1.50) on vcenter2.company.com

Select VM for details: 1
```

### 4. Managing Multiple vCenters

The tools support multiple vCenter servers:

1. **Add Multiple vCenters:**
   ```bash
   ~/vm-credentials
   # Add each vCenter server separately
   ```

2. **Search Across All vCenters:**
   - VM searches automatically query all configured vCenters
   - Results show which vCenter each VM belongs to
   - Cache includes VMs from all vCenters

### 5. Updating and Maintenance

**Update PowerCLI:**
```bash
~/install-powercli
```

**Refresh VM Cache (recommended weekly):**
```bash
cd ~/vm-management-tools
pwsh -File scripts/build-vm-cache-v2.ps1
```

**Add New vCenter:**
```bash
~/vm-credentials
# Select option to add new vCenter
```

## Usage Examples

### Find a VM by Name
```bash
~/vm-manager
# Select option 1
# Enter: "database"
# Results show all VMs with "database" in the name
```

### Find VM by IP Address
```bash
~/vm-manager
# Select option 2  
# Enter: "192.168.1.100"
# Shows VM with that IP address
```

### Get VM Details
```bash
~/vm-manager
# Search for VM first
# Select VM from results
# View detailed information including:
#   - VM name and IP
#   - ESXi host
#   - Power state
#   - vCenter server
#   - Resource allocation
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

### PowerCLI Issues in WSL
If PowerCLI fails to install, use Windows PowerShell:
```bash
powershell.exe -Command "Install-Module VMware.PowerCLI -Scope CurrentUser -Force"
```

### Permission Errors
Ensure secure directories have correct permissions:
```bash
chmod 700 ~/vm-management-tools/secure
```

### VM Cache Issues
If VM searches return no results:
1. Verify vCenter credentials: `~/vm-credentials`
2. Rebuild cache: `cd ~/vm-management-tools && pwsh -File scripts/build-vm-cache-v2.ps1`
3. Check network connectivity to vCenter servers

### Connection Problems
If vCenter connections fail:
- Verify vCenter server addresses are correct
- Check network connectivity: `ping vcenter.company.com`
- Ensure credentials have sufficient permissions
- Check if vCenter certificates are trusted

## License

MIT License - see LICENSE file for details.
