#!/bin/bash

# CrowdStrike Falcon Sensor Installation Script for macOS
# This script downloads and installs the latest CrowdStrike Falcon sensor
# Designed for Mosyle MDM deployment.
# 
# A big thank you to Paul Chernoff for the original script that this is based on :D 
#
# Includes Slack/Teams reporting functionality.
# Version 2.1: Removed CID configuration (handled via separate config profile)

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

# CrowdStrike API credentials - Replace with your actual credentials
clientid="xxx"
secret="xxx"

# --- Reporting Configuration ---
# Add your webhook URLs here.
slackURL=""
teamsURL=""

# Title for the webhook message
appTitle="CrowdStrike Falcon Installation"

# -------------------------------------------------------------------
# Logging & System Info
# -------------------------------------------------------------------

# Logging setup
LOG_FILE="/var/log/crowdstrike_install.log"
# Ensure log file exists and has proper permissions
touch "$LOG_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- System Information ---
# Gather system info for reporting
computerName=$( scutil --get ComputerName )
serialNumber=$( ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}' )
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
osVersion=$( sw_vers -productVersion )
osBuild=$( sw_vers -buildVersion )
UDID=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}')

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
trap webHookMessage EXIT

# -------------------------------------------------------------------
# Reporting Function (Slack & Teams)
# -------------------------------------------------------------------

function webHookMessage() {

    # --- Send to Slack ---
    if [[ -n "$slackURL" ]]; then
        if [[ "$slackURL" == https://hooks.slack.com/* ]]; then
            log "Sending Slack WebHook"
            curl -s -X POST -H 'Content-type: application/json' \
                -d \
                '{
                "blocks": [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": "'"${appTitle}: ${webhookStatus}"'",
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
                                "text": ">*Serial Number & Name:*\n>'"$serialNumber"' on '"$computerName"'"
                            },
                            {
                                "type": "mrkdwn",
                                "text": ">*Operating System:*\n>'"$osVersion ($osBuild)"'"
                            },
                            {
                                "type": "mrkdwn",
                                "text": ">*Current User:*\n>'"$loggedInUser"'"
                            },
                            {
                                "type": "mrkdwn",
                                "text": ">*Details:*\n>'"$reportDetails"'"
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
                                "url": "'"$mosyleComputerURL"'"
                            }
                        ]
                    }
                ]
            }' \
            "$slackURL" > /dev/null 2>&1
        else
            log "Invalid Slack URL format. Skipping Slack report."
        fi
    else
        log "Slack URL not configured. Skipping Slack report."
    fi

    # --- Send to Teams ---
    if [[ -n "$teamsURL" ]]; then
         if [[ "$teamsURL" == https://*.webhook.office.com/* ]]; then
            log "Sending Teams WebHook"
            jsonPayload='{
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": "'$(if [ "$webhookStatus" = "Success" ]; then echo "00C851"; else echo "D50000"; fi)'",
            "summary": "'"${appTitle}: ${webhookStatus}"'",
            "sections": [{
                "activityTitle": "'"${appTitle}: ${webhookStatus}"'",
                "facts": [{
                    "name": "Computer:",
                    "value": "'"$computerName"' ('"$serialNumber"')"
                }, {
                    "name": "User:",
                    "value": "'"$loggedInUser"'"
                }, {
                    "name": "OS Version:",
                    "value": "'"$osVersion ($osBuild)"'"
                }, {
                    "name": "Details:",
                    "value": "'"$reportDetails"'"
                }],
                "markdown": true
            }],
            "potentialAction": [{
                "@type": "OpenUri",
                "name": "View in Mosyle",
                "targets": [{
                    "os": "default",
                    "uri": "'"$mosyleComputerURL"'"
                }]
            }]
        }'

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
# Main Installation Script
# -------------------------------------------------------------------

log "Starting CrowdStrike Falcon sensor installation"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: This script must be run as root or with sudo."
    reportDetails="Insufficient privileges. Run script as root or sudo."
    exit 1
fi

# Check for jq availability (optional but recommended)
if ! command -v jq >/dev/null 2>&1; then
    log "WARNING: 'jq' not installed. Parsing will fallback to 'plutil'. jq is recommended for reliability."
fi

# Validate credentials
if [ "$clientid" = "XXX" ] || [ "$secret" = "XXX" ] || [ "$clientid" = "xxx" ] || [ "$secret" = "xxx" ]; then
    log "ERROR: CrowdStrike API credentials not configured. Please update clientid and secret variables."
    reportDetails="CrowdStrike API credentials not configured."
    exit 1
fi

# Check if already installed
if [ -d "/Applications/Falcon.app" ]; then
    log "CrowdStrike Falcon is already installed."
    webhookStatus="Success"
    reportDetails="CrowdStrike Falcon is already installed."
    exit 0
fi

log "Setting up API authentication"
b64creds=$( printf "$clientid:$secret" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

log "Setting CrowdStrike API endpoint"
# Known endpoint is hardoced to us-2, needs to be updated if you are using a different region.
baseurl="https://api.us-2.crowdstrike.com"

oauthtoken="$baseurl/oauth2/token"
oauthrevoke="$baseurl/oauth2/revoke"
version="0"
sensorlist="$baseurl/sensors/combined/installers/v1?offset=${version}&limit=1&filter=platform%3A%22mac%22"
sensordl="$baseurl/sensors/entities/download-installer/v1"

# --- API Auth with Retry ---
log "Authenticating with CrowdStrike API"
for loop in {1..3}; do
    log "Auth attempt: [$loop / 3]"
    token=$( /usr/bin/curl -s -X POST "$oauthtoken" -H "accept: application/json" -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=${clientid}&client_secret=${secret}" )
    if [ -n "$token" ] && [[ "$token" != *"error"* ]]; then
        log "Authentication successful"
        break
    else
        log "Auth attempt $loop failed."
        sleep 3
    fi
done

if [ -z "$token" ] || [[ "$token" == *"error"* ]]; then
    log "ERROR: Failed to authenticate with CrowdStrike API after 3 attempts"
    reportDetails="Failed to authenticate with CrowdStrike API after 3 attempts."
    exit 1
fi

# Extract bearer token securely with jq preferred
if command -v jq >/dev/null 2>&1; then
    bearer=$(echo "$token" | jq -r '.access_token // empty' 2>/dev/null)
else
    bearer=$(/usr/bin/plutil -extract access_token raw -o - - <<< "$token" 2>/dev/null)
fi

if [ -z "$bearer" ]; then
    log "ERROR: Failed to extract access token"
    reportDetails="Failed to extract access token from API response."
    exit 1
fi

log "Access token extracted successfully"

# --- Get Sensor Info with Retry ---
log "Retrieving sensor information"
for loop in {1..3}; do
    log "Sensor info attempt: [$loop / 3]"
    sensorv=$( /usr/bin/curl -s -X GET "$sensorlist" -H "accept: application/json" -H "authorization: Bearer ${bearer}" )
    
    if [ -z "$sensorv" ]; then
        log "Sensor info attempt $loop failed: Empty response from API"
        sleep 3
        continue
    fi
    
    if command -v jq >/dev/null 2>&1; then
        # Check for API errors using jq
        api_errors=$( echo "$sensorv" | jq -r '.errors // empty' 2>/dev/null )
        if [ -n "$api_errors" ] && [ "$api_errors" != "null" ]; then
            log "Sensor info attempt $loop failed: API returned errors"
            log "API errors: $api_errors"
            sleep 3
            continue
        fi
        
        sensorname=$( echo "$sensorv" | jq -r '.resources[0].name // empty' 2>/dev/null )
        sensorsha=$( echo "$sensorv" | jq -r '.resources[0].sha256 // empty' 2>/dev/null )
    else
        # Fallback plutil method with error checks
        if echo "$sensorv" | /usr/bin/plutil -extract errors raw -o - - 2>/dev/null | grep -q .; then
            log "Sensor info attempt $loop failed: API returned errors"
            log "API response: $sensorv"
            sleep 3
            continue
        fi
        
        sensorname=$( echo "$sensorv" | /usr/bin/plutil -extract resources.0.name raw -o - - 2>/dev/null )
        sensorsha=$( echo "$sensorv" | /usr/bin/plutil -extract resources.0.sha256 raw -o - - 2>/dev/null )
    fi
    
    if [ -n "$sensorname" ] && [ -n "$sensorsha" ]; then
        log "Sensor info retrieved successfully."
        log "Sensor Name: '$sensorname'"
        log "Sensor SHA256: '$sensorsha'"
        break
    else
        log "Sensor info attempt $loop failed: Could not extract sensor information"
        log "Extracted Name: '${sensorname:-'(empty)'}'"
        log "Extracted SHA256: '${sensorsha:-'(empty)'}'"
        sleep 3
    fi
done

if [ -z "$sensorname" ] || [ -z "$sensorsha" ]; then
    log "ERROR: Failed to retrieve sensor information after 3 attempts"
    log "Last API response: $sensorv"
    reportDetails="Failed to retrieve sensor name or SHA256 from API after 3 attempts."
    # Revoke token even on failure
    log "Attempting to revoke OAuth token after failure"
    revoke_response=$(/usr/bin/curl -s -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}" 2>&1)
    if [ $? -eq 0 ]; then
        log "OAuth token revoked successfully"
    else
        log "WARNING: OAuth token revocation may have failed: $revoke_response"
    fi
    exit 1
fi

log "Found sensor: $sensorname (SHA256: $sensorsha)"

# Sanitize sensor name for filename safety (extract basename and remove any path components)
safe_sensorname=$(basename "$sensorname")
# Remove any remaining invalid characters while preserving .pkg extension
safe_sensorname="${safe_sensorname//[^a-zA-Z0-9._-]/_}"
# Trim any trailing underscores to prevent invalid filenames (e.g., .pkg_)
while [[ "$safe_sensorname" == *_ ]]; do
    safe_sensorname="${safe_sensorname%_}"
done
# Trim any trailing whitespace
safe_sensorname="${safe_sensorname%"${safe_sensorname##*[![:space:]]}"}"

log "Downloading CrowdStrike Falcon sensor installer"
log "Target filename: $safe_sensorname"
for loop in {1..10}; do
    log "Download attempt: [$loop / 10]"
    test=$( /usr/bin/curl -s -o /private/tmp/${safe_sensorname} -H "Authorization: Bearer ${bearer}" -w "%{http_code}" "${sensordl}?id=${sensorsha}" )
    if [ "$test" = "200" ]; then
        log "Download successful"
        break
    else
        log "Download attempt $loop failed with HTTP code: $test"
        sleep 5
    fi
done

# Revoke OAuth token
log "Revoking OAuth token"
revoke_response=$(/usr/bin/curl -s -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}" 2>&1)
if [ $? -eq 0 ]; then
    log "OAuth token revoked successfully"
else
    log "WARNING: OAuth token revocation may have failed: $revoke_response"
fi

if [ "$test" != "200" ]; then
    log "ERROR: Download failed after 10 attempts. Exiting."
    reportDetails="Download failed after 10 attempts. Last HTTP code: $test."
    exit 1
fi

# Verify downloaded file
if [ ! -f "/private/tmp/${safe_sensorname}" ]; then
    log "ERROR: Downloaded file not found"
    reportDetails="Downloaded file /private/tmp/${safe_sensorname} not found post-download."
    exit 1
fi

# Log file details before installation
log "Downloaded file at /private/tmp/$safe_sensorname:"
ls -l "/private/tmp/$safe_sensorname" 2>&1 | while read line; do log "$line"; done

# --- SHA256 Verification ---
log "Verifying downloaded file SHA256 hash"
downloadedSha=$( /usr/bin/shasum -a 256 "/private/tmp/${safe_sensorname}" | awk '{print $1}' )

if [ "$downloadedSha" = "$sensorsha" ]; then
    log "SHA256 hash verified successfully."
else
    log "ERROR: SHA256 hash mismatch!"
    log "Expected: $sensorsha"
    log "Got: $downloadedSha"
    reportDetails="SHA256 hash mismatch. File is corrupt or tampered with."
    /bin/rm -f /private/tmp/${safe_sensorname}
    exit 1
fi
# --- End SHA256 Verification ---

log "Installing CrowdStrike Falcon sensor"
install_result=$(/usr/sbin/installer -target / -pkg /private/tmp/${safe_sensorname} 2>&1)
if [ $? -eq 0 ]; then
    log "Installation completed successfully"
else
    log "ERROR: Installation failed - $install_result"
    reportDetails="Installation failed. Installer output: $install_result"
    /bin/rm -f /private/tmp/${safe_sensorname}
    exit 1
fi

# Clean up
log "Cleaning up temporary files"
/bin/rm -f /private/tmp/${safe_sensorname}

# Verify installation
if [ -d "/Applications/Falcon.app" ]; then
    log "CrowdStrike Falcon sensor installation verified"
    log "Installation completed successfully"
    webhookStatus="Success"
    reportDetails="CrowdStrike Falcon sensor was successfully installed."
    exit 0
else
    log "ERROR: Installation verification failed - Falcon.app not found"
    reportDetails="Installation verification failed - /Applications/Falcon.app not found after successful install."
    exit 1
fi