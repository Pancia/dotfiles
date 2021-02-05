#!/usr/bin/env zsh

function sysAudVol() {
    nvram SystemAudioVolume | cut -d$'\t' -f2
}

function disable_osx_startup_chime() {
    echo "$(date '+%x %X')"
    echo "SystemAudioVolume is: '$(sysAudVol | xxd)'"
    if [[ ! "$(sysAudVol)" == '%80' ]]; then
        sudo nvram SystemAudioVolume=%80
        echo "SystemAudioVolume set to: '$(sysAudVol | xxd)'"
    fi
    echo
}

disable_osx_startup_chime 2>&1
