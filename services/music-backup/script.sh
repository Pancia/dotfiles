#!/usr/bin/env bash

echo "$(date): music-backup service started"
music backup
echo "$(date): music-backup service finished"
