#!/bin/bash

# CrowdStrike Falcon Sensor Installation Script for macOS
# This script downloads and installs the latest CrowdStrike Falcon sensor
# Designed for Mosyle MDM deployment.
# 
# A big thank you to Paul Chernoff from Mac Admins Slack for the original script that this is based on :D 
#
# Includes Slack/Teams reporting functionality.
# Version 2.0: Added SHA256 validation, API retries, and webhook validation.

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

# Validate credentials
if [ "$clientid" = "XXX" ] || [ "$secret" = "XXX" ]; then
    log "ERROR: CrowdStrike API credentials not configured. Please update clientid and secret variables."
    reportDetails="CrowdStrike API credentials not configured."
    exit 1
fi

# Check if already installed
if [ -d "/Applications/Falcon.app" ]; then
    log "CrowdStrike Falcon is already installed. Exiting."
    # We'll count this as a "Success" since the goal is to have it installed.
    webhookStatus="Success"
    reportDetails="CrowdStrike Falcon is already installed."
    exit 0
fi

log "Setting up API authentication"
b64creds=$( printf "$clientid:$secret" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

log "Setting CrowdStrike API endpoint"
# Update this if you use a different CS instance (e.g., us-1, gov, etc.)
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

bearer=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$token" )
if [ -z "$bearer" ]; then
    log "ERROR: Failed to extract access token"
    reportDetails="Failed to extract access token from API response."
    exit 1
fi

# --- Get Sensor Info with Retry ---
log "Retrieving sensor information"
for loop in {1..3}; do
    log "Sensor info attempt: [$loop / 3]"
    sensorv=$( /usr/bin/curl -s -X GET "$sensorlist" -H "accept: application/json" -H "authorization: Bearer ${bearer}" )
    sensorname=$( /usr/bin/plutil -extract resources.0.name raw -o - - <<< "$sensorv" )
    sensorsha=$( /usr/bin/plutil -extract resources.0.sha256 raw -o - - <<< "$sensorv" )
    
    if [ -n "$sensorname" ] && [ -n "$sensorsha" ]; then
        log "Sensor info retrieved."
        break
    else
        log "Sensor info attempt $loop failed."
        sleep 3
    fi
done

if [ -z "$sensorname" ] || [ -z "$sensorsha" ]; then
    log "ERROR: Failed to retrieve sensor information after 3 attempts"
    reportDetails="Failed to retrieve sensor name or SHA256 from API after 3 attempts."
    # Revoke token even on failure
    /usr/bin/curl -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}" > /dev/null 2>&1
    exit 1
fi

log "Found sensor: $sensorname (SHA256: $sensorsha)"
log "Downloading CrowdStrike Falcon sensor installer"
for loop in {1..10}; do
    log "Download attempt: [$loop / 10]"
    test=$( /usr/bin/curl -s -o /private/tmp/${sensorname} -H "Authorization: Bearer ${bearer}" -w "%{http_code}" "${sensordl}?id=${sensorsha}" )
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
/usr/bin/curl -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}" > /dev/null 2>&1

if [ "$test" != "200" ]; then
    log "ERROR: Download failed after 10 attempts. Exiting."
    reportDetails="Download failed after 10 attempts. Last HTTP code: $test."
    exit 1
fi

# Verify downloaded file
if [ ! -f "/private/tmp/${sensorname}" ]; then
    log "ERROR: Downloaded file not found"
    reportDetails="Downloaded file /private/tmp/${sensorname} not found post-download."
    exit 1
fi

# --- SHA256 Verification ---
log "Verifying downloaded file SHA256 hash"
downloadedSha=$( /usr/bin/shasum -a 256 "/private/tmp/${sensorname}" | awk '{print $1}' )

if [ "$downloadedSha" = "$sensorsha" ]; then
    log "SHA256 hash verified successfully."
else
    log "ERROR: SHA256 hash mismatch!"
    log "Expected: $sensorsha"
    log "Got: $downloadedSha"
    reportDetails="SHA256 hash mismatch. File is corrupt or tampered with."
    /bin/rm -f /private/tmp/${sensorname}
    exit 1
fi
# --- End SHA256 Verification ---

log "Installing CrowdStrike Falcon sensor"
install_result=$(/usr/sbin/installer -target / -pkg /private/tmp/${sensorname} 2>&1)
if [ $? -eq 0 ]; then
    log "Installation completed successfully"
else
    log "ERROR: Installation failed - $install_result"
    reportDetails="Installation failed. Installer output: $install_result"
    /bin/rm -f /private/tmp/${sensorname}
    exit 1
fi

# Clean up
log "Cleaning up temporary files"
/bin/rm -f /private/tmp/${sensorname}

# Verify installation
if [ -d "/Applications/Falcon.app" ]; then
    log "CrowdStrike Falcon sensor installation verified"
    log "Installation completed successfully"
    # This is our final success state
    webhookStatus="Success"
    reportDetails="CrowdStrike Falcon sensor was successfully installed."
    exit 0
else
    log "ERROR: Installation verification failed - Falcon.app not found"
    reportDetails="Installation verification failed - /Applications/Falcon.app not found after successful install."
    exit 1
fi