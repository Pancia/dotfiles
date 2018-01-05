PLIST=disable_osx_startup_chime.plist

ln -f $PLIST ~/Library/LaunchAgents/$PLIST
sudo launchctl load -w ~/Library/LaunchAgents/$PLIST
