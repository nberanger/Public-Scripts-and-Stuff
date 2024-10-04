#!/bin/bash

# deployZeroTier.sh

#####
# This script will:
# 1. Install ZeroTier in the background
# 2. Connect it to a specified network
# 3. Authorize the device on that network
# 4. Assign the local hostname to the device in ZeroTier Central
# 5. Send a formatted Slack notification with the deployment status (if a webhook is provided)
#####
# version 3.1 October 4, 2024 - nberanger
#####
# Revision notes:
#
# 1.0 July 30, 2024 - nberanger
# - initial version of script, modified from script provided by itsCasper from Mac Admins Slack
# - added logging and some additional comments
# 
# 1.1 August 22, 2024 - nberanger
# - added device authorization on the network when joining
# - added assignment of hostname to the device in ZeroTier Central
#
# 1.2 October 3, 2024 - nberanger
# - updated script to use full path for zerotier-cli
# - improved error handling and logging
# - ensured latest version of ZeroTier is always installed
#
# 2.0 October 3, 2024 - nberanger
# - added formatted Slack notifications for deployment status
# - included network name in notifications
# - improved error reporting in Slack messages
# - updated Slack message for better readability
# - added a button in Slack message to view the network in ZeroTier Central
#
# 3.0 October 4, 2024 - nberanger
# - added function to check for latest ZeroTier version using GitHub API
# - improved ZeroTier installation process to check current version and update if necessary
# - enhanced logging for ZeroTier version checks and installation process
# - reorganized script structure to improve readability, and allow easier maintenance
# - added check for 'jq' dependency and provided installation instructions if not found
# - moved all configuration variables to the top of the script
# - improved error handling and input validation for required variables
#
# 3.1 October 4, 2024 - nberanger
# - added enhanced retry mechanism for API calls with exponential backoff
# - removed dependency on 'jq', using native tools 'grep' and 'sed' for JSON processing instead
# - updated logging to be consistent and more informative throughout the entire script
# - added check for Slack webhook URL, only attempt to send notifications if it is set
####

#####
# Configuration Variables
#####
# ZeroTier API token (required)
ZEROTIER_API_TOKEN="api-token-here"

# ZeroTier network ID (required)
ZEROTIER_NETWORK_ID="network-id-here"

# Slack webhook URL for notifications (optional, leave empty to disable Slack notifications)
SLACK_WEBHOOK=""

# Log file path (optional, default is /var/log/deployZeroTier.log)
LOG_FILE="/var/log/deployZeroTier.log"

# Full path to zerotier-cli (optional, default is /usr/local/bin/zerotier-cli)
ZEROTIER_CLI="/usr/local/bin/zerotier-cli"

#####
# Functions
#####
# Function for error handling
handle_error() {
    local error_message="$1"
    errors+="$error_message\n"
    echo "$(date): Error: $error_message" | tee -a "$LOG_FILE"
}

# Function to send Slack notification
send_slack_notification() {
    if ! slack_enabled; then
        log_message "Slack webhook not configured. Skipping notification."
        return
    fi

    local status="$1"
    local hostname="$2"
    local member_id="$3"
    local network_name="$4"
    local network_id="$5"
    local errors="$6"

    local color
    local icon
    case "$status" in
        "Success")
            color="#36a64f"
            icon=":large_green_circle:"
            ;;
        "Failure")
            color="#ff0000"
            icon=":red_circle:"
            ;;
        "Interrupted")
            color="#FFA500"
            icon=":large_orange_circle:"
            ;;
        *)
            color="#808080"
            icon=":white_circle:"
            ;;
    esac
    local title="*ZeroTier Deployment: $status* $icon"

    local message=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "pretext": "$title",
            "fields": [
                {
                    "title": "Device Name:",
                    "value": "$hostname",
                    "short": true
                },
                {
                    "title": "Network Name:",
                    "value": "$network_name",
                    "short": true
                },
                {
                    "title": "Device ID:",
                    "value": "$member_id",
                    "short": true
                },
                {
                    "title": "Network ID:",
                    "value": "$network_id",
                    "short": true
                },
                {
                    "title": "",
                    "value": "",
                    "short": false
                },
                {
                    "title": "Errors:",
                    "value": "${errors:-None}",
                    "short": false
                }
            ],
            "actions": [
                {
                    "type": "button",
                    "text": "View in ZeroTier Central",
                    "url": "https://my.zerotier.com/network/$network_id",
                    "style": "primary"
                }
            ]
        }
    ]
}
EOF
)

    log_message "Sending Slack notification"
    response=$(curl -s -X POST -H 'Content-type: application/json' --data "$message" "$SLACK_WEBHOOK")
    log_message "Slack API response: $response"

    if [ "$response" = "ok" ]; then
        log_message "Slack notification sent successfully"
    else
        log_message "Error sending Slack notification: $response"
    fi
}

cleanup() {
    log_message "Script interrupted. Performing cleanup..."
    
    # Remove any partially downloaded ZeroTier installation package
    if [ -f "/tmp/ZeroTier One.pkg" ]; then
        log_message "Removing partial ZeroTier installation package"
        rm -f "/tmp/ZeroTier One.pkg"
    fi
    
    # If ZeroTier was partially installed, attempt to remove it
    if [ -f "/Library/Application Support/ZeroTier/One/uninstall.sh" ]; then
        log_message "Removing partial ZeroTier installation"
        sudo "/Library/Application Support/ZeroTier/One/uninstall.sh"
    fi
    
    # If network was joined but setup didn't complete, leave the network
    if [ -n "$ZEROTIER_NETWORK_ID" ] && sudo "$ZEROTIER_CLI" listnetworks | grep -q "$ZEROTIER_NETWORK_ID"; then
        log_message "Leaving partially joined ZeroTier network"
        sudo "$ZEROTIER_CLI" leave "$ZEROTIER_NETWORK_ID"
    fi
    
    # Log point when an interruption occurs
    log_message "Script interrupted at line $BASH_LINENO"
    
    # If Slack is enabled, send a notification about the interruption
    if slack_enabled; then
        send_slack_notification "Interrupted" "$hostname" "" "" "$ZEROTIER_NETWORK_ID" "Script interrupted during execution"
    fi
    
    log_message "Cleanup completed. Exiting."
    exit 1
}

# ZeroTier functions
get_latest_zerotier_version() {
    local latest_version=$(curl -s https://api.github.com/repos/zerotier/ZeroTierOne/releases/latest | sed -n 's/.*"tag_name": "\(.*\)".*/\1/p')
    if [ -z "$latest_version" ]; then
        echo "Error: Unable to fetch latest ZeroTier version"
        return 1
    fi
    echo "${latest_version#v}"  # This will remove the 'v' prefix from the version string if it is found
}

check_zerotier() {
    local latest_version=$(get_latest_zerotier_version)
    if [ $? -ne 0 ]; then
        log_message "$latest_version. Skipping version check."
        echo 3
        return 3  # Error fetching version
    fi
    log_message "Latest ZeroTier version: $latest_version"

    if [ -x "$ZEROTIER_CLI" ]; then
        local current_version=$("$ZEROTIER_CLI" -v | cut -d' ' -f4)
        log_message "Current ZeroTier version: $current_version"
        
        if [ "$current_version" = "$latest_version" ]; then
            log_message "ZeroTier is installed and up to date."
            echo 0
            return 0  # Version is up to date
        else
            log_message "ZeroTier is installed but not the latest version. Will update."
            echo 2
            return 2  # Version needs to be updated
        fi
    else
        log_message "ZeroTier is not installed or not executable at $ZEROTIER_CLI"
        echo 1
        return 1  # Not installed
    fi
}

remove_zerotier() {
    log_message "Removing existing ZeroTier installation"
    if [ -f "/Library/Application Support/ZeroTier/One/uninstall.sh" ]; then
        sudo "/Library/Application Support/ZeroTier/One/uninstall.sh" || handle_error "Failed to uninstall existing ZeroTier"
    else
        log_message "ZeroTier uninstaller not found. Proceeding with installation."
    fi
}

install_zerotier() {
    log_message "Installing/Updating ZeroTier..."
    
    # Remove any existing ZeroTier installer
    log_message "Removing any existing ZeroTier package"
    sudo rm -f "/tmp/ZeroTier One.pkg" || handle_error "Failed to remove existing ZeroTier package"

    # Download latest version of ZeroTier installer
    log_message "Downloading latest ZeroTier package"
    curl -s https://download.zerotier.com/dist/ZeroTier%20One.pkg >"/tmp/ZeroTier One.pkg" || handle_error "Failed to download ZeroTier package"

    # Install ZeroTier
    log_message "Installing ZeroTier package"
    sudo installer -pkg "/tmp/ZeroTier One.pkg" -target / || handle_error "Failed to install ZeroTier package"

    # Clean up
    log_message "Cleaning up temporary files"
    sudo rm -f "/tmp/ZeroTier One.pkg" || log_message "Warning: Failed to remove temporary ZeroTier package"

    # Verify installation
    zerotier_status=$(check_zerotier)
    if [ "$zerotier_status" = "0" ]; then
        log_message "ZeroTier installed/updated successfully"
    else
        handle_error "ZeroTier installation/update failed. Status: $zerotier_status"
    fi
}

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM

# Set up logging
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# API call retry with increasing delays (default is up to 5 attempts)
api_call_with_retry() {
    local max_attempts=5
    local attempt=1
    local timeout=1
    local response=""
    while [ $attempt -le $max_attempts ]; do
        response=$(curl -s -m 10 "$@")
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            echo "$response"
            return 0
        fi
        log_message "API call failed. Attempt $attempt of $max_attempts. Retrying in $timeout seconds..."
        sleep $timeout
        timeout=$((timeout * 2 + RANDOM % 2))  # Gradually increasing random wait times between retries
        attempt=$((attempt + 1))
    done
    log_message "API call failed after $max_attempts attempts."
    return 1
}

# Function to check if Slack notifications are enabled
slack_enabled() {
    [ -n "$SLACK_WEBHOOK" ]
}

# Main script execution
hostname=$(hostname)
success=true
errors=""

# Check for ZeroTier installation and version
zerotier_output=$(check_zerotier)
zerotier_status=${zerotier_output##*$'\n'}
log_message "ZeroTier check returned status: $zerotier_status"

case $zerotier_status in
    0)  
        log_message "ZeroTier is up to date. Proceeding with network configuration."
        ;;
    1)  
        log_message "ZeroTier needs to be installed."
        install_zerotier || success=false
        ;;
    2)
        log_message "ZeroTier needs to be updated."
        remove_zerotier
        install_zerotier || success=false
        ;;
    3)
        log_message "Error fetching ZeroTier version. Proceeding with existing installation."
        ;;
    *)
        handle_error "Unexpected error checking ZeroTier status: $zerotier_status"
        success=false
        ;;
esac

if $success; then
    # Check if devices is already a member of the network
    log_message "Checking if already a member of ZeroTier network: $ZEROTIER_NETWORK_ID"
    network_check=$(sudo "$ZEROTIER_CLI" listnetworks | grep "$ZEROTIER_NETWORK_ID")
    
    if [ -z "$network_check" ]; then
        # Join ZeroTier network
        log_message "Joining computer to ZeroTier network: $ZEROTIER_NETWORK_ID"
        join_response=$(sudo "$ZEROTIER_CLI" join "$ZEROTIER_NETWORK_ID")
        log_message "Join response: $join_response"
        
        if ! echo "$join_response" | grep -q "200 join OK"; then
            log_message "Failed to join ZeroTier network. Response: $join_response"
            success=false
            errors+="Failed to join ZeroTier network. "
        else
            log_message "Successfully joined ZeroTier network"
        fi
    else
        log_message "Already a member of ZeroTier network $ZEROTIER_NETWORK_ID"
    fi
fi

if $success; then
    # Get device Member ID
    member_id=$(sudo "$ZEROTIER_CLI" info | awk '{print $3}')
    log_message "The Member ID for this device is: $member_id"

    # Authorize the device on the ZeroTier network
    log_message "Authorizing device on ZeroTier network"
    auth_response=$(api_call_with_retry -X POST "https://api.zerotier.com/api/v1/network/$ZEROTIER_NETWORK_ID/member/$member_id" \
        -H "Authorization: Bearer $ZEROTIER_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"config":{"authorized":true}}')

    if [ $? -ne 0 ]; then
        log_message "Failed to authorize device on the network after multiple attempts"
        success=false
        errors+="Failed to authorize device. "
    else
        log_message "Full authorization response: $auth_response"
        if echo "$auth_response" | grep -q '"authorized":true'; then
            log_message "Device successfully authorized on the network"
        else
            log_message "Failed to authorize device on the network"
            success=false
            errors+="Authorization failed. "
        fi
    fi
fi

if $success; then
    # Get the computer's hostname
    hostname=$(hostname)
    log_message "Computer hostname: $hostname"

    # Update the device name in ZeroTier Central
    log_message "Updating device name in ZeroTier Central"
    name_update_response=$(api_call_with_retry -X POST "https://api.zerotier.com/api/v1/network/$ZEROTIER_NETWORK_ID/member/$member_id" \
        -H "Authorization: Bearer $ZEROTIER_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$hostname\"}")

    if [ $? -ne 0 ]; then
        log_message "Failed to update device name in ZeroTier Central after multiple attempts"
        success=false
        errors+="Failed to update device name. "
    else
        log_message "Name update response: $name_update_response"
        if echo "$name_update_response" | grep -q "\"name\":\"$hostname\""; then
            log_message "Device name successfully updated in ZeroTier Central"
        else
            log_message "Failed to update device name in ZeroTier Central"
            success=false
            errors+="Failed to update device name. "
        fi
    fi
fi

if slack_enabled; then
    # Get ZeroTier network name for Slack notification
    log_message "Retrieving ZeroTier network name"
    network_info=$(api_call_with_retry -H "Authorization: Bearer $ZEROTIER_API_TOKEN" \
        "https://api.zerotier.com/api/v1/network/$ZEROTIER_NETWORK_ID")
    log_message "Network info API response: $network_info"

    network_name=$(echo "$network_info" | grep -Eo '"name":"[^"]+"' | sed 's/"name":"//;s/"//')
    if [ -z "$network_name" ]; then
        log_message "Failed to retrieve network name from API response"
        network_name="Unknown"
    else
        log_message "Successfully retrieved network name: $network_name"
    fi

    # Send Slack notification
    status=$([ "$success" = true ] && echo "Success" || echo "Failure")
    send_slack_notification "$status" "$hostname" "$member_id" "$network_name" "$ZEROTIER_NETWORK_ID" "$errors"
else
    log_message "Slack webhook not configured. Skipping network name retrieval and notification."
fi

if $success; then
    log_message "ZeroTier deployment completed successfully"
    exit 0
else
    log_message "ZeroTier deployment encountered errors: $errors"
    exit 1
fi