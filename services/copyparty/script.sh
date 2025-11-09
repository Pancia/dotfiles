#!/usr/bin/env zsh

echo "$(date): copyparty service started"
cd ~/ProtonDrive/copyparty/
copyparty -c copyparty.conf
