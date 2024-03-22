#!/bin/sh

# mosyle-dockutil.sh

#####
# **Based on script originally created by admarice**
# https://macadmins.slack.com/archives/C1YV1CJSJ/p1710444473330659?thread_ts=1710443277.857659&cid=C1YV1CJSJ
# 
# Checks to make sure that required apps are installed, and then organizes apps on dock
# 
##### History #####
# 
# v1.0 March 18, 2024 - nberanger
# modified script from adamrice
# 
#####

# assign log file, and send output to file
log="/var/log/dockUtil.log"

exec 1>> $log 2>&1

# Check for required apps. If not found set a delay until they are found
until [[ -a "/Applications/Microsoft Excel.app" && -a "/Applications/Microsoft Word.app" && -a "/Applications/Microsoft Powerpoint.app" && -a "/Applications/zoom.us.app" && -a "/Applications/Google Chrome.app" ]]; do
	delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  +  Required apps not installed, waiting [$delay] seconds"
    sleep $delay
done
echo "$(date) | Apps are here, lets carry on"

# Get current logged in user
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
uid=$(id -u "$currentUser")

userHome=$(dscl . -read /users/${currentUser} NFSHomeDirectory | cut -d " " -f 2)
plist="${userHome}/Library/Preferences/com.apple.dock.plist"

if [[ -x "/usr/local/bin/dockutil" ]]; then
    docku="/usr/local/bin/dockutil"
else
    echo "/usr/local/bin/dockutil not installed in /usr/local/bin, exiting"
    exit 1
fi

# Clean out the current dock
until ! sudo -u "$currentUser" grep -q "Messages.app" "/Users/$currentUser/Library/Preferences/com.apple.dock.plist"; do
	sudo -u "$currentUser" /usr/local/bin/dockutil --remove all --no-restart "/Users/$currentUser/Library/Preferences/com.apple.dock.plist"
	sleep 7
    killall cfprefsd Dock
	sleep 7
done
echo "$(date) | Dock Reset"

killall cfprefsd Dock
echo "$(date) | Pausing for 10s"
sleep 10
echo "$(date) | Complete"

# Place apps in dock 
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/System/Applications/Launchpad.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Slack.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/zoom.us.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Google Chrome.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Microsoft Word.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Microsoft Excel.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Microsoft PowerPoint.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Dropbox.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/1Password.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/System/Applications/Managed Software Center.app" --no-restart /Users/$currentUser
sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Applications/Self-Service.app" --no-restart /Users/$currentUser

sudo -u "$currentUser" /usr/local/bin/dockutil --add "/Users/$currentUser/Downloads/" --view auto --display stack --sort dateadded --section others --no-restart /Users/$currentUser
sleep 10


killall cfprefsd Dock
exit 0
