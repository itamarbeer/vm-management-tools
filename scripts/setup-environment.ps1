#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Ubuntu VM Environment Setup Script for VM Management Tools
.DESCRIPTION
    Sets up complete environment on fresh Ubuntu VM including:
    - PowerShell Core installation
    - PowerCLI module installation
    - Required dependencies and tools
    - Directory structure creation
    - Permission setup
.NOTES
    Run this script after PowerShell is installed, or use the companion bash script first
#>

param(
    [switch]$SkipPowerShellInstall,
    [switch]$Verbose
)

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = $Reset
    )
    Write-Host "${Color}${Message}${Reset}"
}

function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Test-WSLEnvironment {
    # Check if running in WSL
    if (Test-Path "/proc/version") {
        $versionContent = Get-Content "/proc/version" -Raw
        return $versionContent -match "Microsoft|WSL"
    }
    return $false
}

function Install-PowerCLI {
    Write-ColorOutput "Installing VMware PowerCLI..." $Cyan
    
    # Check if running in WSL
    $isWSL = Test-WSLEnvironment
    if ($isWSL) {
        Write-ColorOutput "WSL environment detected - using WSL-compatible installation method..." $Yellow
    }
    
    try {
        # Set PowerShell execution policy
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        
        # Install NuGet provider if needed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-ColorOutput "Installing NuGet package provider..." $Yellow
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
            } catch {
                Write-ColorOutput "NuGet installation failed, trying alternative method..." $Yellow
                # Alternative method for WSL
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -SkipPublisherCheck
            }
        }
        
        # Set PSGallery as trusted
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Write-ColorOutput "Setting PSGallery as trusted repository..." $Yellow
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        
        # Install PowerCLI with WSL-specific parameters
        Write-ColorOutput "Installing VMware PowerCLI modules..." $Yellow
        if ($isWSL) {
            # WSL-specific installation with additional parameters
            Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -AcceptLicense
        } else {
            Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber
        }
        
        # Import PowerCLI
        Write-ColorOutput "Importing PowerCLI modules..." $Yellow
        Import-Module VMware.PowerCLI -Force
        
        # Configure PowerCLI settings
        Write-ColorOutput "Configuring PowerCLI settings..." $Yellow
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false | Out-Null
        
        Write-ColorOutput "PowerCLI installation completed successfully!" $Green
        
        # Display PowerCLI version
        $powerCLIVersion = Get-Module VMware.PowerCLI -ListAvailable | Select-Object -First 1
        Write-ColorOutput "Installed PowerCLI Version: $($powerCLIVersion.Version)" $Green
        
        return $true
    } catch {
        Write-ColorOutput "Failed to install PowerCLI: $($_.Exception.Message)" $Red
        
        # If WSL, provide specific troubleshooting
        if ($isWSL) {
            Write-ColorOutput "WSL-specific troubleshooting:" $Yellow
            Write-ColorOutput "1. Try running: Install-Module VMware.PowerCLI -Scope CurrentUser -Force -SkipPublisherCheck" $Yellow
            Write-ColorOutput "2. If that fails, try: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12" $Yellow
            Write-ColorOutput "3. Consider using native Windows PowerShell for PowerCLI operations" $Yellow
        }
        
        return $false
    }
}

function Setup-DirectoryStructure {
    Write-ColorOutput "Setting up directory structure..." $Cyan
    
    $directories = @(
        "$HOME/project-vc-manage",
        "$HOME/project-vc-manage/scripts",
        "$HOME/project-vc-manage/secure",
        "$HOME/project-vc-manage/logs",
        "$HOME/protective-scripts",
        "$HOME/protective-scripts/secure",
        "$HOME/protective-scripts/logs",
        "$HOME/Powercli",
        "$HOME/Powercli/snapshotsemail",
        "$HOME/Powercli/snapshotsemail/secure"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-ColorOutput "Created directory: $dir" $Yellow
            } catch {
                Write-ColorOutput "Failed to create directory: $dir - $($_.Exception.Message)" $Red
            }
        } else {
            Write-ColorOutput "Directory already exists: $dir" $Green
        }
    }
    
    # Set proper permissions
    Write-ColorOutput "Setting directory permissions..." $Yellow
    try {
        # Make secure directories more restrictive
        $secureDirs = @(
            "$HOME/project-vc-manage/secure",
            "$HOME/protective-scripts/secure",
            "$HOME/Powercli/snapshotsemail/secure"
        )
        
        foreach ($secureDir in $secureDirs) {
            if (Test-Path $secureDir) {
                # Use chmod to set 700 permissions (owner read/write/execute only)
                $chmodResult = Start-Process -FilePath "chmod" -ArgumentList "700", $secureDir -Wait -PassThru -NoNewWindow
                if ($chmodResult.ExitCode -eq 0) {
                    Write-ColorOutput "Set secure permissions for: $secureDir" $Green
                } else {
                    Write-ColorOutput "Warning: Could not set secure permissions for: $secureDir" $Yellow
                }
            }
        }
    } catch {
        Write-ColorOutput "Warning: Could not set all directory permissions: $($_.Exception.Message)" $Yellow
    }
}

function Install-RequiredTools {
    Write-ColorOutput "Installing additional required tools..." $Cyan
    
    $tools = @(
        @{Name="curl"; Package="curl"},
        @{Name="wget"; Package="wget"},
        @{Name="jq"; Package="jq"},
        @{Name="git"; Package="git"}
    )
    
    foreach ($tool in $tools) {
        if (-not (Test-Command $tool.Name)) {
            Write-ColorOutput "Installing $($tool.Name)..." $Yellow
            try {
                $result = Start-Process -FilePath "sudo" -ArgumentList "apt-get", "install", "-y", $tool.Package -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -eq 0) {
                    Write-ColorOutput "$($tool.Name) installed successfully!" $Green
                } else {
                    Write-ColorOutput "Failed to install $($tool.Name)" $Red
                }
            } catch {
                Write-ColorOutput "Error installing $($tool.Name): $($_.Exception.Message)" $Red
            }
        } else {
            Write-ColorOutput "$($tool.Name) is already installed" $Green
        }
    }
}

function Test-Environment {
    Write-ColorOutput "Testing environment setup..." $Cyan
    
    $tests = @()
    
    # Test PowerShell
    if (Test-Command "pwsh") {
        $psVersion = $PSVersionTable.PSVersion
        $tests += @{Name="PowerShell"; Status="OK"; Version=$psVersion}
    } else {
        $tests += @{Name="PowerShell"; Status="MISSING"; Version="N/A"}
    }
    
    # Test PowerCLI
    try {
        $powerCLI = Get-Module VMware.PowerCLI -ListAvailable | Select-Object -First 1
        if ($powerCLI) {
            $tests += @{Name="PowerCLI"; Status="OK"; Version=$powerCLI.Version}
        } else {
            $tests += @{Name="PowerCLI"; Status="MISSING"; Version="N/A"}
        }
    } catch {
        $tests += @{Name="PowerCLI"; Status="ERROR"; Version="N/A"}
    }
    
    # Test tools
    $toolsToTest = @("curl", "wget", "jq", "git")
    foreach ($tool in $toolsToTest) {
        if (Test-Command $tool) {
            try {
                $version = & $tool --version 2>$null | Select-Object -First 1
                $tests += @{Name=$tool; Status="OK"; Version=$version}
            } catch {
                $tests += @{Name=$tool; Status="OK"; Version="Available"}
            }
        } else {
            $tests += @{Name=$tool; Status="MISSING"; Version="N/A"}
        }
    }
    
    # Display results
    Write-ColorOutput "`nEnvironment Test Results:" $Cyan
    Write-ColorOutput "=========================" $Cyan
    
    foreach ($test in $tests) {
        $statusColor = switch ($test.Status) {
            "OK" { $Green }
            "MISSING" { $Red }
            "ERROR" { $Red }
            default { $Yellow }
        }
        
        $versionInfo = if ($test.Version -ne "N/A") { " ($($test.Version))" } else { "" }
        Write-ColorOutput "$($test.Name.PadRight(15)): $($test.Status)$versionInfo" $statusColor
    }
    
    # Check directories
    Write-ColorOutput "`nDirectory Structure:" $Cyan
    Write-ColorOutput "====================" $Cyan
    
    $dirsToCheck = @(
        "$HOME/project-vc-manage",
        "$HOME/protective-scripts",
        "$HOME/Powercli/snapshotsemail/secure"
    )
    
    foreach ($dir in $dirsToCheck) {
        if (Test-Path $dir) {
            Write-ColorOutput "$($dir.PadRight(40)): EXISTS" $Green
        } else {
            Write-ColorOutput "$($dir.PadRight(40)): MISSING" $Red
        }
    }
}

function Show-NextSteps {
    Write-ColorOutput "`nNext Steps:" $Cyan
    Write-ColorOutput "===========" $Cyan
    Write-ColorOutput "1. Setup credentials:" $Yellow
    Write-ColorOutput "   pwsh -File ~/project-vc-manage/scripts/securefile-v2.ps1" $White
    Write-ColorOutput ""
    Write-ColorOutput "2. Build VM cache:" $Yellow
    Write-ColorOutput "   ~/protective-scripts/build-vm-cache.sh" $White
    Write-ColorOutput ""
    Write-ColorOutput "3. Start VM manager:" $Yellow
    Write-ColorOutput "   ~/project-vc-manage/scripts/vm-search-manager-v3.sh" $White
}

# Main execution
function Main {
    Write-ColorOutput "VM Management Tools Setup" $Cyan
    Write-ColorOutput "=========================" $Cyan
    Write-ColorOutput ""
    
    # Check if running as root
    if ($env:USER -eq "root") {
        Write-ColorOutput "Warning: Running as root. Consider running as a regular user." $Yellow
        Write-ColorOutput ""
    }
    
    # Update package list
    Write-ColorOutput "Updating package list..." $Yellow
    try {
        $result = Start-Process -FilePath "sudo" -ArgumentList "apt-get", "update" -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) {
            Write-ColorOutput "Package list updated successfully!" $Green
        } else {
            Write-ColorOutput "Warning: Package list update failed" $Yellow
        }
    } catch {
        Write-ColorOutput "Warning: Could not update package list: $($_.Exception.Message)" $Yellow
    }
    
    # Install required tools
    Install-RequiredTools
    
    # Install PowerCLI
    $powerCLIInstalled = Install-PowerCLI
    if (-not $powerCLIInstalled) {
        $isWSL = Test-WSLEnvironment
        if ($isWSL) {
            Write-ColorOutput "PowerCLI installation failed in WSL environment." $Yellow
            Write-ColorOutput "This is a known compatibility issue. The setup will continue..." $Yellow
            Write-ColorOutput "You can install PowerCLI manually later or use Windows PowerShell." $Yellow
            Write-ColorOutput ""
        } else {
            Write-ColorOutput "PowerCLI installation failed. Please check the errors above." $Red
            return 1
        }
    }
    
    # Setup directory structure
    Setup-DirectoryStructure
    
    # Test environment
    Test-Environment
    
    # Show next steps
    Show-NextSteps
    
    Write-ColorOutput "`nSetup completed!" $Green
    
    # Check if WSL and PowerCLI failed
    $isWSL = Test-WSLEnvironment
    if ($isWSL -and -not $powerCLIInstalled) {
        Write-ColorOutput "`nNote: PowerCLI installation failed in WSL." $Yellow
        Write-ColorOutput "Use Windows PowerShell for full PowerCLI functionality." $Yellow
        Write-ColorOutput ""
    }
    
    Write-ColorOutput "VM management tools are ready to use." $Green
    
    return 0
}

# Run main function
exit (Main)
