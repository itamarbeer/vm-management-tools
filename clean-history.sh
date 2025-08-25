#!/bin/bash

# Script to clean git history and make project look brand new

echo "🧹 Cleaning Git History - Making Project Look Brand New"
echo "======================================================="

# Backup current state
echo "Creating backup branch..."
git branch backup-$(date +%Y%m%d_%H%M%S)

# Create orphan branch (no history)
echo "Creating clean branch..."
git checkout --orphan clean-main

# Add all files
echo "Adding all files..."
git add .

# Create single clean commit
echo "Creating clean initial commit..."
git commit -m "Initial commit - VM Management Tools

Complete VM management solution with:
- Enhanced VM search and management (v3.0)
- Secure credential management
- Automated VM cache building
- PowerShell integration
- Self-contained project structure
- Interactive setup and validation

Ready to use with vmmanage and vmcred commands."

# Replace main branch
echo "Replacing main branch..."
git branch -D main
git branch -m main

# Force push to GitHub (this will rewrite history)
echo "⚠️  WARNING: This will rewrite GitHub history!"
echo "Press Enter to continue or Ctrl+C to cancel..."
read

git push -f origin main

echo "✅ Git history cleaned! Project now looks brand new."
echo "🔄 All commits squashed into single 'Initial commit'"
