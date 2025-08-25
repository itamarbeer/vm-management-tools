# VM Management Tools - Setup Guide

Automated setup for VM management tools on Ubuntu systems.

## Installation

### Automatic Setup
```bash
curl -sSL https://raw.githubusercontent.com/itamarbeer/vm-management-tools/main/scripts/full-setup.sh | bash
```

### Manual Setup
```bash
git clone https://github.com/itamarbeer/vm-management-tools.git
cd vm-management-tools
./scripts/full-setup.sh
```

## What Gets Installed

- PowerShell Core (latest version)
- VMware PowerCLI modules
- Required system packages (git, curl, wget, jq)
- Project directory structure
- Convenient command shortcuts

## Directory Structure
```
~/vm-management-tools/
├── scripts/
│   ├── full-setup.sh              # Main setup script
│   ├── vm-search-manager-v3.sh    # VM manager
│   ├── securefile-v2.ps1          # Credential management
│   ├── build-vm-cache-v2.ps1      # Cache builder
│   └── setup-environment.ps1      # PowerShell setup
├── secure/                        # Encrypted credentials
└── logs/                          # Operation logs
```

## Post-Installation

1. **Configure Credentials**
   ```bash
   ~/vm-credentials
   ```

2. **Build VM Cache**
   ```bash
   cd ~/vm-management-tools
   pwsh -File scripts/build-vm-cache-v2.ps1
   ```

3. **Start VM Manager**
   ```bash
   ~/vm-manager
   ```

## Shortcuts Created

- `~/vm-manager` - Launch VM search manager
- `~/vm-credentials` - Configure vCenter credentials
- `~/install-powercli` - Install/update PowerCLI

## Troubleshooting

### PowerCLI Installation Issues
For WSL environments, PowerCLI may fail with PowerShell Core. Use Windows PowerShell:
```bash
powershell.exe -Command "Install-Module VMware.PowerCLI -Scope CurrentUser -Force"
```

### Permission Issues
Secure directories need proper permissions:
```bash
chmod 700 ~/vm-management-tools/secure
```

### Legacy Data Migration
If you have an existing `~/project-vc-manage` directory, the setup will automatically migrate:
- Credential files from `secure/`
- Log files from `logs/`

## System Requirements

- Ubuntu 20.04+ or WSL2
- Internet connection
- sudo privileges for package installation
- Minimum 1GB free disk space

## Verification

Test your installation:
```bash
# Check PowerShell
pwsh --version

# Check PowerCLI (if installed)
pwsh -c "Get-Module VMware.PowerCLI -ListAvailable"

# Test VM manager
~/vm-manager --help
```
