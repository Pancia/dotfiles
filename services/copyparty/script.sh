#!/usr/bin/env zsh

echo "$(date): copyparty service started"

cd ~/ProtonDrive/ && copyparty -c copyparty/copyparty.conf
