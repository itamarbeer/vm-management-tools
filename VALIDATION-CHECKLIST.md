# VM Management Tools - Validation Checklist

Testing checklist to verify installation and functionality.

## Pre-Testing Setup

### Environment Verification
- [ ] PowerShell Core installed: `pwsh --version`
- [ ] PowerCLI modules available: `pwsh -c "Get-Module VMware.PowerCLI -ListAvailable"`
- [ ] Directory structure created
- [ ] Shortcuts created: `~/vm-manager`, `~/vm-credentials`, `~/install-powercli`

### File Permissions
- [ ] Secure directory permissions: `ls -la ~/vm-management-tools/secure/`
- [ ] Scripts are executable: `ls -la ~/vm-management-tools/scripts/`

## Core Functionality Tests

### 1. Credential Management
- [ ] Run credential setup: `~/vm-credentials`
- [ ] Add vCenter server successfully
- [ ] Credentials encrypted and stored
- [ ] Can retrieve credentials without errors

### 2. VM Cache Building
- [ ] Build cache: `cd ~/vm-management-tools && pwsh -File scripts/build-vm-cache-v2.ps1`
- [ ] Cache file created successfully
- [ ] No connection errors to vCenter
- [ ] VM data populated correctly

### 3. VM Search Manager
- [ ] Launch manager: `~/vm-manager`
- [ ] Interactive menu displays
- [ ] Search by VM name works
- [ ] Search by IP address works
- [ ] VM details display correctly
- [ ] Multiple vCenter support works

### 4. PowerCLI Integration
- [ ] PowerCLI commands execute without errors
- [ ] vCenter connections establish successfully
- [ ] VM operations complete successfully
- [ ] Proper error handling for failed connections

## Performance Tests

### Search Performance
- [ ] VM search completes in reasonable time (<5 seconds)
- [ ] Large VM lists handled properly
- [ ] Memory usage remains stable during operations

### Connection Handling
- [ ] Multiple vCenter connections work
- [ ] Connection timeouts handled gracefully
- [ ] Credential validation works properly

## Error Handling Tests

### Invalid Inputs
- [ ] Invalid VM names handled properly
- [ ] Invalid IP addresses rejected
- [ ] Non-existent vCenter servers handled
- [ ] Network connectivity issues handled

### Permission Issues
- [ ] Missing credentials handled gracefully
- [ ] Insufficient vCenter permissions reported clearly
- [ ] File permission issues reported

## WSL Compatibility Tests

### PowerCLI in WSL
- [ ] PowerCLI installs via Windows PowerShell method
- [ ] PowerCLI commands work in WSL environment
- [ ] File paths resolve correctly
- [ ] Network connectivity works properly

## Final Validation

### Complete Workflow Test
1. [ ] Fresh installation completes successfully
2. [ ] Credential setup completes without errors
3. [ ] VM cache builds successfully
4. [ ] VM search and management works end-to-end
5. [ ] All shortcuts function properly

### Documentation Verification
- [ ] README instructions are accurate
- [ ] Setup guide matches actual installation
- [ ] Troubleshooting steps resolve common issues
- [ ] All file references are correct

## Sign-off

- [ ] All tests passed
- [ ] No critical issues identified
- [ ] Ready for production use

**Tested by:** ________________  
**Date:** ________________  
**Environment:** ________________
