#!/bin/sh

# sonomaCompatible.sh

#####
# This script check to see if a computer's model matches the regex pattern of macOS Sonoma compatible computers.
# It was written to be used as a custom attribute in Moysle
# If the computer model matches the pattern then a value of 'YES' is returned, otherwise the value is 'NO'
# talkingmoose maintains a regex list here: https://gist.github.com/talkingmoose/1b852e5d4fc8e76b4400ca2e4b3f3ad0#file-sonoma-compatible-macs-regex
#####
# version 1.0, nberanger, June 21, 2024
#####

hardwareCheck=$(
# Check the model of the mac
model=$(sysctl -n hw.model)
sonomaCompatible="NO"

# Regex pattern
pattern="^(Mac(1[3-9]|BookPro1[5-8]|BookAir([89]|10)|Pro[7-9]|Book[0-9]{2,})|iMac(Pro[0-9]+|1[89]|[2-9][0-9])|Macmini[89]|VirtualMac),[0-9]+$"

# Check if the mac model matches with the regex pattern
if [[ "$model" =~ $pattern ]]; then
    sonomaCompatible="YES"
    echo "$sonomaCompatible"
else
    echo "$sonomaCompatible"
fi
)

echo "$hardwareCheck"

exit