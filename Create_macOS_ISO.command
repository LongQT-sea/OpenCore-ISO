#!/bin/bash
# Copyright (c) 2024–2025, LongQT-sea
# macOS Full Installer ISO Creator
# Downloads official macOS installers from Apple servers and create a true DVD-format macOS installer ISO file.
# Intended for use with Proxmox, QEMU, VirtualBox, and VMware.

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
selected_idx=0

# Function to print colored output
print_color() {
    color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to check if the script has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_color $YELLOW "This script requires sudo privileges to run createinstallmedia."
        print_color $YELLOW "You’ll be prompted for password after the macOS installer finishes downloading."
		echo ""
    fi
}

# Function to get available installers
get_installers() {
    print_color $GREEN "Fetching available macOS installers from Apple server..."
    installers=$(softwareupdate --list-full-installers 2>/dev/null | grep "* Title:" | sed 's/^[[:space:]]*//')
    
    if [ -z "$installers" ]; then
        print_color $RED "No installers found. Please check your internet connection."
        exit 1
    fi
    
    # Parse installer information into arrays
    IFS=$'\n'
    installer_array=($installers)
    unset IFS
    
    # Initialize arrays
    titles=()
    versions=()
    sizes=()
    builds=()
    
    for installer in "${installer_array[@]}"; do
        # Extract information using sed
        title=$(echo "$installer" | sed -n 's/.*Title: \([^,]*\).*/\1/p')
        version=$(echo "$installer" | sed -n 's/.*Version: \([^,]*\).*/\1/p')
        size=$(echo "$installer" | sed -n 's/.*Size: \([^,]*\).*/\1/p')
        build=$(echo "$installer" | sed -n 's/.*Build: \([^,]*\).*/\1/p')
        
        titles+=("$title")
        versions+=("$version")
        sizes+=("$size")
        builds+=("$build")
    done
}

# Function to display installer menu
display_menu() {
    print_color $YELLOW "\nAvailable macOS Installers:\n"
    
    for i in "${!titles[@]}"; do
        # Convert size from KiB to GB for readability
        size_kb="${sizes[$i]//KiB/}"
        size_gb=$(echo "scale=1; $size_kb / 1048576" | bc)
        
        printf "${BLUE}%2d)${NC} %-20s ${GREEN}v%-8s${NC} (${YELLOW}%.1f GB${NC}, Build: %s)\n" \
               $((i+1)) "${titles[$i]}" "${versions[$i]}" "$size_gb" "${builds[$i]}"
    done
    
    echo
    print_color $YELLOW "0) Exit"
    echo
}

# Function to get user selection
get_selection() {
    local max_option=${#titles[@]}
    local selection
    
    while true; do
        read -p "Enter your choice (0-$max_option): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [ "$selection" -eq 0 ]; then
                print_color $YELLOW "Exiting..."
                exit 0
            elif [ "$selection" -ge 1 ] && [ "$selection" -le "$max_option" ]; then
                selected_idx=$((selection - 1))
                return 0
            fi
        fi
        
        print_color $RED "Invalid selection. Please enter a number between 0 and $max_option."
    done
}

# Function to download installer
download_installer() {
    local idx=$1
    local version="${versions[$idx]}"
    local title="${titles[$idx]}"
    
    print_color $GREEN "\nDownloading $title version $version..."
    print_color $YELLOW "This may take a while depending on your internet connection..."
    
    # Run the download command
    if softwareupdate --fetch-full-installer --full-installer-version "$version"; then
        print_color $GREEN "Download completed successfully!"
        return 0
    else
        print_color $RED "Download failed. Please try again."
        return 1
    fi
}

# Function to create ISO
create_iso() {
    local idx=$1
    local title="${titles[$idx]}"
    local version="${versions[$idx]}"
    
    # Determine installer app name based on title
    local installer_name
    case "$title" in
        "macOS Tahoe")
            installer_name="Install macOS Tahoe"
            ;;
        "macOS Sequoia")
            installer_name="Install macOS Sequoia"
            ;;
        "macOS Sonoma")
            installer_name="Install macOS Sonoma"
            ;;
        "macOS Ventura")
            installer_name="Install macOS Ventura"
            ;;
        "macOS Monterey")
            installer_name="Install macOS Monterey"
            ;;
        "macOS Big Sur")
            installer_name="Install macOS Big Sur"
            ;;
        "macOS Catalina")
            installer_name="Install macOS Catalina"
            ;;
        "macOS Mojave")
            installer_name="Install macOS Mojave"
            ;;
        "macOS High Sierra")
            installer_name="Install macOS High Sierra"
            ;;
        *)
            installer_name="Install $title"
            ;;
    esac
    
    local installer_path="/Applications/${installer_name}.app"
    local iso_name="${title// /_}_${version}"
    local sparse_image="$HOME/Desktop/${iso_name}.sparseimage"
    local iso_file="$HOME/Desktop/${iso_name}.iso"
    local volume_name="${iso_name}_installer"
    
    # Check if ISO already exists and ask user
    if [ -f "$iso_file" ]; then
        print_color $YELLOW "ISO file already exists: $iso_file"
        read -p "Do you want to overwrite it? (y/n): " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            print_color $YELLOW "Removing existing ISO file..."
            rm -f "$iso_file"
        else
            print_color $YELLOW "Operation cancelled. Exiting."
            return 1
        fi
    fi
    
    # Check if sparse image already exists and remove it
    if [ -f "$sparse_image" ]; then
        print_color $YELLOW "Removing existing sparse image..."
        rm -f "$sparse_image"
    fi
    
    # Check if installer exists
    if [ ! -d "$installer_path" ]; then
        print_color $RED "Installer not found at: $installer_path"
        print_color $RED "Please ensure the installer downloaded correctly."
        return 1
    fi
    
    print_color $GREEN "\nCreating ISO for $title version $version..."
    
    # Step 1: Create sparse image
    print_color $BLUE "Step 1/4: Creating sparse image..."
    if hdiutil create -size 20g -volname "$volume_name" -fs HFS+ -type SPARSE -attach "$sparse_image"; then
        print_color $GREEN "Sparse image created and mounted"
    else
        print_color $RED "Failed to create sparse image"
        return 1
    fi
    
    # Step 2: Create install media
    print_color $BLUE "Step 2/4: Creating install media (this requires sudo)..."
    if sudo "${installer_path}/Contents/Resources/createinstallmedia" --volume "/Volumes/$volume_name" --nointeraction; then
        print_color $GREEN "Install media created"
    else
        print_color $RED "Failed to create install media"
        hdiutil detach "/Volumes/$volume_name" 2>/dev/null || true
        rm -f "$sparse_image" 2>/dev/null || true
        return 1
    fi
    
    # Step 3: Detach volume
    print_color $BLUE "Step 3/4: Detaching volume..."
    # After createinstallmedia, the volume is renamed to the installer name
    if hdiutil detach "/Volumes/$installer_name" 2>/dev/null || hdiutil detach "/Volumes/$installer_name" -force 2>/dev/null; then
        print_color $GREEN "Volume detached successfully"
    else
        print_color $RED "Failed to detach volume automatically"
        print_color $YELLOW "Please manually eject the '$installer_name' volume from Finder"
        read -p "Press Enter when ready to continue..."
    fi
    
    # Give the system a moment to complete the unmount
    sleep 2
    
    # Step 4: Create hybrid ISO
    print_color $BLUE "Step 4/4: Creating hybrid ISO ..."
    if hdiutil makehybrid -hfs -udf -o "$iso_file" "$sparse_image"; then
        print_color $GREEN "ISO created successfully"
    else
        print_color $RED "Failed to create ISO"
        rm -f "$sparse_image" 2>/dev/null || true
        return 1
    fi
    
    # Clean up sparse image
    print_color $BLUE "Cleaning up temporary files..."
    rm -f "$sparse_image"
    
    print_color $GREEN "\n=========================================="
    print_color $GREEN "ISO creation completed successfully!"
    print_color $GREEN "ISO file location: $iso_file"
    print_color $GREEN "Installer preserved at: $installer_path"
    print_color $GREEN "=========================================="
    
    # Show ISO file info
    if [ -f "$iso_file" ]; then
        local iso_size=$(du -h "$iso_file" | cut -f1)
        print_color $YELLOW "\nISO file size: $iso_size"
    fi
    
    return 0
}

# Main script execution
main() {
    clear
    print_color $GREEN "macOS Full Installer ISO Creator"
    print_color $GREEN "============================"
    
    # Check for required tools
    for tool in softwareupdate hdiutil diskutil bc; do
        if ! command -v $tool &> /dev/null; then
            print_color $RED "Error: Required tool $tool is not found."
            exit 1
        fi
    done
    
    # Check sudo access early
    check_sudo
    
    # Get available installers
    get_installers
    
    # Display menu and get selection
    display_menu
    get_selection
    
    # Download installer
    if download_installer $selected_idx; then
        # Create ISO
        create_iso $selected_idx
    else
        print_color $RED "Download failed. Exiting."
        exit 1
    fi
}

# Run main function
main
