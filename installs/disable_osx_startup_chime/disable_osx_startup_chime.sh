PLIST=me.pancia.disable_osx_startup_chime.plist

sudo launchctl unload -w /Library/LaunchDaemons/$PLIST 2> /dev/null
sudo ln -f $PLIST /Library/LaunchDaemons/$PLIST
sudo launchctl load -w /Library/LaunchDaemons/$PLIST
