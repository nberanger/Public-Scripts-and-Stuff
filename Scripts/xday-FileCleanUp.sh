#!/bin/bash

# Xday-FilecleanUp.sh

#####
# version 1.0 October 21, 2024 - nberanger
#####

#####
# This script will:
# 1. Scan a specified directory for files of various ages based on configured values.
# 2. Count and list files in different age categories (to be deleted within 1 week, 2 days, 1 day, and immediately).
# 3. Delete files that are equal to or older than the 'deleteNow' age setting.
# 4. Send a detailed report to Slack using a webhook.
#####

#####
# Configuration Variables
#####

# Leave set to true to log output to $logFile. Comment out or set false to print only to terminal.
enableLogging=true  

# Leave set to true to enable verbose logging. Comment out or set false to disable.
# enableVerboseLogging=true

# Enable file deletion. Comment out or set false to disable
enableFileDeletion=true

# Files that fall within this range of days old will be deleted within 1 week.
# (must assign exactly five values representing ages in days)
deleteIn1Week=(83 84 85 86 87)
# Files this number of days old will be deleted within 2 days
deleteIn2days=88
# Files this number of days old will be deleted within 1 day
deleteIn1day=89
# Files this number and older will be deleted when found
deleteNow=90
# Directory to scan for files
directoryToScan=""

# Path to log file
logFile="/var/log/${deleteNow}day-FileCleanUp.log"
# Script name, used in logging
scriptName="${deleteNow}day-FileCleanUp.sh"
# Current date and time, used in logging
currentDate=$(date +"%Y-%m-%d %H:%M:%S")

# Slack webhook URL for posting messages, set your own URL here.
slackWebhookUrl=""

# DO NOT MODIFY ANYTHING BELOW THIS LINE
################################################################################

# If verbose logging is enabled, ensure standard logging is also enabled
if [ "$enableVerboseLogging" = true ]; then
    enableLogging=true
fi

#####
# Functions
#####

# Function to handle errors and log them if logging is enabled
handle_error() {
    local error_message="$1"
    if [ "$enableLogging" = true ]; then
        echo "$(date): Error: $error_message" >> "$logFile"
    fi
    echo "$(date): Error: $error_message" >&2
}

# Function to scan for files by age and return the count
scan_files_by_age() {
    local age=$1
    if [ -n "$age" ]; then  # Check if age is not empty
        local count=$(find "$directoryToScan" -type f -mtime "$age" | wc -l)
        echo "$count"
    else
        echo "0"  # Return 0 if age is not valid
    fi
}

# Function to list files by age
list_files_by_age() {
    local age=$1
    if [ -n "$age" ]; then  # Check if age is not empty
        find "$directoryToScan" -type f -mtime "$age"
    else
        echo "No files found."
    fi
}

# Function to post messages to a Slack channel using Block Kit
post_to_slack() {
    local start_time="$1"
    local end_time="$2"
    local count_1week="$3"
    local count_2days=$(echo "$4" | tr -d ' ')  # Remove all spaces
    local count_1day=$(echo "$5" | tr -d ' ')   # Remove all spaces
    local count_now=$(echo "$6" | tr -d ' ')    # Remove all spaces
    local files_1week="$7"
    local files_2days="$8"
    local files_1day="$9"
    local files_deleted="${10}"

    # Function to create a bullet list from file paths
    create_bullet_list() {
        local IFS=$'\n'
        local files=($1)
        local json=""
        for file in "${files[@]}"; do
            if [ -n "$file" ]; then
                if command -v jq >/dev/null 2>&1; then
                    escaped_file=$(echo "$file" | jq -R .)
                    json+="{\"type\":\"rich_text_section\",\"elements\":[{\"type\":\"text\",\"text\":$escaped_file}]},"
                else
                    json+="{\"type\":\"rich_text_section\",\"elements\":[{\"type\":\"text\",\"text\":\"$file\"}]},"
                fi
            fi
        done
        echo "${json%,}"  # Remove trailing comma
    }

    # Create bullet lists
    local list_1week=$(create_bullet_list "$files_1week")
    local list_2days=$(create_bullet_list "$files_2days")
    local list_1day=$(create_bullet_list "$files_1day")
    local list_deleted=$(create_bullet_list "$files_deleted")

    # Function to determine the appropriate icon and text
    get_icon() {
        local count=$1
        if [ "$count" -eq 0 ]; then
            echo "No files found. :white_check_mark:"
        elif [ "$count" -eq 1 ]; then
            echo ":warning: \`$count\` file found. :warning:"
        else
            echo ":warning: \`$count\` files found. :warning:"
        fi
    }

    # Get formatted text with icons based on file counts
    local text_1week=$(get_icon "$count_1week")
    local text_2days=$(get_icon "$count_2days")
    local text_1day=$(get_icon "$count_1day")

    # Determine the color based on the age of files found
    local attachment_color="#36a64f"  # Default green
    if [ "$count_now" -gt 0 ]; then
        attachment_color="#ff0000"  # Red if files to delete now
    elif [ "$count_1day" -gt 0 ]; then
        attachment_color="#ffa500"  # Orange if files to delete in 1 day
    elif [ "$count_2days" -gt 0 ]; then
        attachment_color="#ffa500"  # Orange if files to delete in 2 days
    elif [ "$count_1week" -gt 0 ]; then
        attachment_color="#ffd500"  # Yellow if files to delete in 1 week (changed from light blue)
    fi

    # Construct the JSON payload
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$attachment_color",
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": ":broom:  Cleaning out FTP Files Older than $deleteNow Days  :broom:",
                        "emoji": true
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Started:* $start_time"
                    }
                },
                {
                    "type": "divider"
                },
EOF
)

    if [ "$count_now" -gt 0 ]; then
        local files_to_show=("${@:10:20}")  # Get up to 20 files from the 10th argument onwards
        local remaining_files=$((count_now - ${#files_to_show[@]}))

        # Debug logging
        echo "DEBUG: First 5 files in files_to_show:" >> "$logFile"
        printf '%s\n' "${files_to_show[@]:0:5}" >> "$logFile"

        local deleted_files_list=""
        for file in "${files_to_show[@]}"; do
            if command -v jq >/dev/null 2>&1; then
                escaped_file=$(echo "$file" | jq -R .)
                deleted_files_list+="{\"type\":\"rich_text_section\",\"elements\":[{\"type\":\"text\",\"text\":$escaped_file}]},"
            else
                deleted_files_list+="{\"type\":\"rich_text_section\",\"elements\":[{\"type\":\"text\",\"text\":\"$file\"}]},"
            fi
        done
        deleted_files_list=${deleted_files_list%,}

        # Debug logging
        echo "DEBUG: deleted_files_list:" >> "$logFile"
        echo "$deleted_files_list" >> "$logFile"

        payload+=$(cat <<EOF
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": ":exclamation: *Files older than \`$deleteNow\` days were found* :exclamation:"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*The following files in \`$directoryToScan\` were older than \`$deleteNow\` days and have been automatically deleted* :wastebasket::"
                    }
                },
                {
                    "type": "rich_text",
                    "elements": [
                        {
                            "type": "rich_text_list",
                            "style": "bullet",
                            "elements": [
                                $deleted_files_list
                            ]
                        }
                    ]
                },
EOF
)
        if [ "$remaining_files" -gt 0 ]; then
            payload+=$(cat <<EOF
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*...and \`$remaining_files\` more files.*"
                    }
                },
EOF
)
        fi
        payload+=$(cat <<EOF
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Total Number of Files Deleted:* \`$count_now\`\n(_view the log file for the complete list of deleted files_)\n\`$logFile\`"
                    }
                },
                {
                    "type": "divider"
                },
EOF
)
    fi

    # Continue with the rest of the payload
    payload+=$(cat <<EOF
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Files to be deleted within 1 day:*\n$text_1day"
                    }
                },
                {
                    "type": "rich_text",
                    "elements": [
                        {
                            "type": "rich_text_list",
                            "style": "bullet",
                            "elements": [
                                $list_1day
                            ]
                        }
                    ]
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Files to be deleted within 2 days:*\n$text_2days"
                    }
                },
                {
                    "type": "rich_text",
                    "elements": [
                        {
                            "type": "rich_text_list",
                            "style": "bullet",
                            "elements": [
                                $list_2days
                            ]
                        }
                    ]
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Files to be deleted within 1 week:*\n$text_1week"
                    }
                },
                {
                    "type": "rich_text",
                    "elements": [
                        {
                            "type": "rich_text_list",
                            "style": "bullet",
                            "elements": [
                                $list_1week
                            ]
                        }
                    ]
                },
                {
                    "type": "divider"
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "*Completed:* $end_time"
                    }
                }
            ]
        }
    ]
}
EOF
)

    # Send the JSON payload to Slack
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$slackWebhookUrl"
}

# Verbose logging function
verbose_log() {
    if [ "$enableVerboseLogging" = true ]; then
        echo "VERBOSE: $1" >&2
    fi
}

# Function to move files to trash
move_to_trash() {
    local file="$1"
    if [ "$enableFileDeletion" = true ]; then
        mv "$file" ~/.Trash/
        echo "Moved to trash: $file"
    else
        echo "Would move to trash (dry run): $file"
    fi
}

# Main script execution
{
    # Check if log file is writable
    if [ "$enableLogging" = true ]; then
        echo "Attempting to write to log file: $logFile" >&2
        if ! touch "$logFile" 2>/dev/null; then
            echo "Error: Unable to write to log file $logFile. Please check permissions." >&2
            echo "Continuing without logging..." >&2
            enableLogging=false
        else
            echo "Successfully touched log file" >&2
            ls -l "$logFile" >&2
        fi
    fi

    # Redirect output to log file if logging is enabled
    if [ "$enableLogging" = true ]; then
        echo "Redirecting output to log file" >&2
        exec > >(tee -a "$logFile") 2>&1
    fi

    # Log the start of the script execution
    echo "----------------------------------------"
    echo "$currentDate | $scriptName"
    echo "----------------------------------------"

    # Show logging status message
    if [ "$enableLogging" = true ]; then
        if [ "$enableVerboseLogging" = true ]; then
            # Output to terminal and log file
            echo "*** VERBOSE LOGGING IS ENABLED ***"
        else
            # Output to terminal and log file
            echo "*** LOGGING IS ENABLED ***"
        fi
    else
        # Output to terminal only
        echo "*** LOGGING IS DISABLED ***"
    fi
    echo ""

    # Start searching for files in the specified directory
    echo "Searching $directoryToScan..."
    echo ""

    # Count files aged deleteIn1Week days
    totalCountIn1Week=0
    for age in "${deleteIn1Week[@]}"; do
        count=$(scan_files_by_age "$age")
        totalCountIn1Week=$((totalCountIn1Week + count))
    done
    printf "File(s) to be deleted within 1 week: %2d\n" "$totalCountIn1Week"

    # Count files aged deleteIn2days days
    countIn2days=$(scan_files_by_age "$deleteIn2days")
    printf "File(s) to be deleted within 2 days: %2d\n" "$countIn2days"

    # Count files aged deleteIn1day days
    countIn1day=$(scan_files_by_age "$deleteIn1day")
    printf "File(s) to be deleted within 1 day: %2d\n\n" "$countIn1day"

    # Count and potentially delete files aged deleteNow days or older
    countNow=0
    files_deleted=()
    while IFS= read -r file; do
        ((countNow++))
        files_deleted+=("$file")
        if [ "$enableFileDeletion" = true ]; then
            move_to_trash "$file"
        fi
        # Debug logging
        echo "DEBUG: Added file to files_deleted: $file" >> "$logFile"
    done < <(find "$directoryToScan" -type f -mtime +"$deleteNow")

    # Debug logging
    echo "DEBUG: Total files in files_deleted: ${#files_deleted[@]}" >> "$logFile"

    printf "%d file(s) older than %d day(s) found in: %s\n" "$countNow" "$deleteNow" "$directoryToScan"
    if [ "$enableFileDeletion" = true ]; then
        echo "These files have been moved to the trash."
    else
        echo "File deletion is disabled. No files were moved to the trash."
    fi

    # New section for additional output
    echo ""
    echo "----------------------------------------"
    echo "Files scheduled to be deleted:"
    echo "----------------------------------------"

    # Generate file lists and store in variables
    filesIn1Week=""
    for age in "${deleteIn1Week[@]}"; do
        filesIn1Week+="$(list_files_by_age "$age")\n"
    done
    filesIn1Week=$(echo -e "$filesIn1Week" | sed '/^$/d')  # Remove empty lines

    filesIn2Days=$(list_files_by_age "$deleteIn2days")
    filesIn1Day=$(list_files_by_age "$deleteIn1day")

    # Verbose output
    verbose_log "Files to be deleted within 1 week:"
    verbose_log "$filesIn1Week"
    verbose_log "Files to be deleted within 2 days:"
    verbose_log "$filesIn2Days"
    verbose_log "Files to be deleted within 1 day:"
    verbose_log "$filesIn1Day"
    verbose_log "Files older than $deleteNow days (to be deleted now):"
    verbose_log "${files_deleted[*]}"

    # Debug logging before calling post_to_slack
    echo "DEBUG: First 5 files in files_deleted:" >> "$logFile"
    printf '%s\n' "${files_deleted[@]:0:5}" >> "$logFile"

    post_to_slack "$currentDate" "$(date +"%Y-%m-%d %H:%M:%S")" \
        "$totalCountIn1Week" "$countIn2days" "$countIn1day" "$countNow" \
        "$filesIn1Week" "$filesIn2Days" "$filesIn1Day" "${files_deleted[@]}"

    # Verbose Output. After calling post_to_slack.
    verbose_log "post_to_slack called with:"
    verbose_log "totalCountIn1Week: $totalCountIn1Week"
    verbose_log "countIn2days: $countIn2days"
    verbose_log "countIn1day: $countIn1day"
    verbose_log "countNow: $countNow"
    verbose_log "filesIn1Week: $filesIn1Week"
    verbose_log "filesIn2Days: $filesIn2Days"
    verbose_log "filesIn1Day: $filesIn1Day"
    verbose_log "files_deleted: ${files_deleted[*]}"
} || { handle_error "Failed to execute file scans"; exit 1; }

# At the end of the script, add:
if [ "$enableLogging" = true ]; then
    echo "Script execution completed. Final log file status:" >&2
    ls -l "$logFile" >&2
fi