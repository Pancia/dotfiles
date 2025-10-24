#!/usr/bin/env zsh

echo "$(date): copyparty service started"

cd ~/private/ && copyparty -c copyparty.conf
