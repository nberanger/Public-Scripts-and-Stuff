#!/bin/bash

# CrowdStrike Falcon Sensor Uninstallation Script for macOS
# This script uninstalls the CrowdStrike Falcon sensor
# Designed for Mosyle MDM deployment.
# 
# A big thank you to Paul Chernoff for the original script that this is based on :D 
#
# Includes Slack/Teams reporting functionality.
# Version 1.0: Initial uninstall script.

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

# --- Reporting Configuration ---
# Add your webhook URLs here.
slackURL="xxx"
teamsURL="xxx"

# Title for the webhook message
appTitle="CrowdStrike Falcon Uninstallation"

# -------------------------------------------------------------------
# Logging & System Info
# -------------------------------------------------------------------

# Logging setup with error handling
LOG_FILE="/var/log/crowdstrike_uninstall.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
if ! exec 1> >(tee -a "$LOG_FILE" 2>&1); then
    echo "ERROR: Could not set up logging to $LOG_FILE" >&2
    exit 1
fi
exec 2> >(tee -a "$LOG_FILE" >&2)

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to escape JSON strings
escape_json() {
    local string="$1"
    # Escape backslashes first
    string="${string//\\/\\\\}"
    # Escape quotes
    string="${string//\"/\\\"}"
    # Escape newlines
    string="${string//$'\n'/\\n}"
    # Escape carriage returns
    string="${string//$'\r'/\\r}"
    # Escape tabs
    string="${string//$'\t'/\\t}"
    echo "$string"
}

# --- System Information ---
# Gather system info for reporting with error handling
computerName=$( scutil --get ComputerName 2>/dev/null ) || computerName="Unknown"
serialNumber=$( ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformSerialNumber/{print $4}' ) || serialNumber="Unknown"
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil 2>/dev/null | awk '/Name :/ { print $3 }' ) || loggedInUser="Unknown"
osVersion=$( sw_vers -productVersion 2>/dev/null ) || osVersion="Unknown"
osBuild=$( sw_vers -buildVersion 2>/dev/null ) || osBuild="Unknown"
UDID=$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | awk -F\" '/IOPlatformUUID/{print $(NF-1)}') || UDID="Unknown"

# --- Mosyle URL (for reporting) ---
# Update this if you use a different Mosyle instance (e.g., EU, US)
mosyleURL="https://mybusiness.mosyle.com"
mosyleComputerURL="${mosyleURL}/#device_${UDID}"

# --- Webhook Status Variables ---
# These will be updated before exit
webhookStatus="Error"
reportDetails="Script exited unexpectedly."

# --- Trap ---
# This ensures the webHookMessage function is called when the script exits (0 or 1)
# Use a guard to prevent recursion
TRAP_ARMED=1
trap 'if [[ $TRAP_ARMED -eq 1 ]]; then TRAP_ARMED=0; webHookMessage; fi' EXIT

# -------------------------------------------------------------------
# Reporting Function (Slack & Teams)
# -------------------------------------------------------------------

# Helper function to build Slack message JSON
buildSlackMessage() {
    local escaped_appTitle=$(escape_json "${appTitle}: ${webhookStatus}")
    local escaped_serialNumber=$(escape_json "$serialNumber")
    local escaped_computerName=$(escape_json "$computerName")
    local escaped_osVersion=$(escape_json "$osVersion ($osBuild)")
    local escaped_loggedInUser=$(escape_json "$loggedInUser")
    local escaped_reportDetails=$(escape_json "$reportDetails")
    # URLs should not be escaped - keep as-is
    # local escaped_mosyleURL removed - use $mosyleComputerURL directly
    
    cat <<EOF
{
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "${escaped_appTitle}",
                "emoji": true
            }
        },
        {
            "type": "divider"
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": ">*Serial Number & Name:*\n>${escaped_serialNumber} on ${escaped_computerName}"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Operating System:*\n>${escaped_osVersion}"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Current User:*\n>${escaped_loggedInUser}"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Details:*\n>${escaped_reportDetails}"
                }
            ]
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "View computer in Mosyle",
                        "emoji": true
                    },
                    "style": "primary",
                    "action_id": "actionId-0",
                    "url": "${mosyleComputerURL}"
                }
            ]
        }
    ]
}
EOF
}

function webHookMessage() {
    # --- Send to Slack ---
    if [[ -n "$slackURL" ]]; then
        if echo "$slackURL" | grep -qE "https://hooks\.slack\.com/services/"; then
            log "Sending Slack WebHook"
            slack_message=$(buildSlackMessage)
            curl -s -X POST -H 'Content-type: application/json' \
                -d "$slack_message" \
                "$slackURL" > /dev/null 2>&1
        else
            log "Invalid Slack URL format. Skipping Slack report."
        fi
    else
        log "Slack URL not configured. Skipping Slack report."
    fi

    # --- Send to Teams ---
    if [[ -n "$teamsURL" ]]; then
        if echo "$teamsURL" | grep -qE "https://.*\.webhook\.office\.com/.*"; then
            log "Sending Teams WebHook"
            
            # Compute theme color before JSON construction
            if [[ "$webhookStatus" = "Success" ]]; then
                themeColor="00C851"
            else
                themeColor="D50000"
            fi
            
            # Escape variables for JSON (except URLs which should remain unescaped)
            local escaped_appTitle=$(escape_json "${appTitle}: ${webhookStatus}")
            local escaped_computerName=$(escape_json "$computerName")
            local escaped_serialNumber=$(escape_json "$serialNumber")
            local escaped_loggedInUser=$(escape_json "$loggedInUser")
            local escaped_osVersion=$(escape_json "$osVersion ($osBuild)")
            local escaped_reportDetails=$(escape_json "$reportDetails")
            # URLs should not be escaped - keep as-is
            # local escaped_mosyleURL removed - use $mosyleComputerURL directly
            
            jsonPayload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "${themeColor}",
    "summary": "${escaped_appTitle}",
    "sections": [{
        "activityTitle": "${escaped_appTitle}",
        "facts": [{
            "name": "Computer:",
            "value": "${escaped_computerName} (${escaped_serialNumber})"
        }, {
            "name": "User:",
            "value": "${escaped_loggedInUser}"
        }, {
            "name": "OS Version:",
            "value": "${escaped_osVersion}"
        }, {
            "name": "Details:",
            "value": "${escaped_reportDetails}"
        }],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View in Mosyle",
        "targets": [{
            "os": "default",
            "uri": "${mosyleComputerURL}"
        }]
    }]
}
EOF
)
            # Send the JSON payload using curl
            curl -s -X POST -H "Content-Type: application/json" -d "$jsonPayload" "$teamsURL" > /dev/null 2>&1
        else
            log "Invalid Teams URL format. Skipping Teams report."
        fi
    else
        log "Teams URL not configured. Skipping Teams report."
    fi
}

# -------------------------------------------------------------------
# System Extension Check Function
# -------------------------------------------------------------------

# Function to check if CrowdStrike system extension is running
checkSystemExtension() {
    log "Checking for CrowdStrike system extensions"
    
    # Get list of system extensions and check for CrowdStrike
    system_extensions=$(systemextensionsctl list 2>&1)
    exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log "WARNING: Could not list system extensions (exit code: $exit_code)"
        log "Output: $system_extensions"
        # If we can't check, proceed with caution but log the issue
        return 0
    fi
    
    # Check for CrowdStrike Falcon system extension bundle identifier
    # Format: *	*	X9E956P446	com.crowdstrike.falcon.Agent (7.30/202.02)	Falcon Sensor	[activated enabled]
    if echo "$system_extensions" | grep -qi "com.crowdstrike.falcon.Agent"; then
        log "ERROR: CrowdStrike system extension is still present on the system"
        log "System extension details:"
        echo "$system_extensions" | grep -i "com.crowdstrike.falcon.Agent"
        
        # Check if it's activated/enabled
        if echo "$system_extensions" | grep -qi "com.crowdstrike.falcon.Agent.*activated.*enabled"; then
            log "ERROR: CrowdStrike system extension is activated and enabled"
        fi
        
        return 1
    else
        log "No CrowdStrike system extensions found. Safe to proceed with uninstall."
        return 0
    fi
}

# -------------------------------------------------------------------
# Main Uninstallation Script
# -------------------------------------------------------------------

log "Starting CrowdStrike Falcon sensor uninstallation"

# Check if Falcon.app exists
if [ ! -d "/Applications/Falcon.app" ]; then
    log "CrowdStrike Falcon is not installed. Nothing to uninstall."
    webhookStatus="Warning"
    reportDetails="CrowdStrike Falcon is not installed. Nothing to uninstall."
    exit 0
fi

# Check if system extension is still running
# If found, send notification but continue with uninstall attempt
if ! checkSystemExtension; then
    log "WARNING: System extension is still present on the system. Attempting uninstall anyway."
    webhookStatus="Warning"
    reportDetails="CrowdStrike system extension is still present on the system. Attempting uninstall anyway."
    
    # Send immediate notification to Slack about the system extension
    if [[ -n "$slackURL" ]] && echo "$slackURL" | grep -qE "https://hooks\.slack\.com/services/"; then
        log "Sending immediate Slack notification about system extension"
        slack_message=$(buildSlackMessage)
        curl -s -X POST -H 'Content-type: application/json' \
            -d "$slack_message" \
            "$slackURL" > /dev/null 2>&1
    fi
    
    # Continue with uninstall attempt instead of exiting
    log "Proceeding with uninstall attempt despite system extension presence"
fi

# Check if falconctl exists
FALCONCTL="/Applications/Falcon.app/Contents/Resources/falconctl"
if [ ! -f "$FALCONCTL" ]; then
    log "ERROR: falconctl not found at $FALCONCTL"
    reportDetails="falconctl not found. Cannot proceed with uninstallation."
    exit 1
fi

# Run uninstall command
# Note: No sudo needed - Mosyle MDM runs scripts with root privileges
log "Running uninstall command: $FALCONCTL uninstall"
uninstall_result=$("$FALCONCTL" uninstall 2>&1)
uninstall_exit_code=$?

if [[ $uninstall_exit_code -eq 0 ]]; then
    log "Uninstall command completed successfully"
    
    # Wait a moment for the uninstall to complete
    sleep 2
    
    # Verify uninstallation
    if [ ! -d "/Applications/Falcon.app" ]; then
        log "CrowdStrike Falcon sensor uninstallation verified"
        log "Uninstallation completed successfully"
        webhookStatus="Success"
        reportDetails="CrowdStrike Falcon sensor was successfully uninstalled."
        exit 0
    else
        log "WARNING: Uninstall command succeeded but Falcon.app still exists"
        log "Output: $uninstall_result"
        webhookStatus="Warning"
        escaped_uninstall_result=$(escape_json "$uninstall_result")
        reportDetails="Uninstall command succeeded but Falcon.app still exists. Manual cleanup may be required. Output: $escaped_uninstall_result"
        exit 0
    fi
else
    log "ERROR: Uninstall command failed with exit code $uninstall_exit_code"
    log "Output: $uninstall_result"
    # Escape the uninstall result for webhook
    escaped_uninstall_result=$(escape_json "$uninstall_result")
    reportDetails="Uninstall command failed. Exit code: $uninstall_exit_code. Output: $escaped_uninstall_result"
    exit 1
fi

