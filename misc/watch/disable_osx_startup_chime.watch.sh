#!/usr/bin/env zsh

function disable_osx_startup_chime() {
    local sysAudVol=$(nvram SystemAudioVolume | cut -d$'\t' -f2)
    if [[ ! "$sysAudVol" == '%80' ]]; then
        local sysAudVol_binary="$(echo ${sysAudVol} | xxd)"
        echo "$(date '+%x %X') -> $sysAudVol_binary"
        #TODO: add to sudoers on install ? with args?
        #   $(whoami) ALL=(ALL) NOPASSWD: /usr/sbin/nvram SystemAudioVolume=%80
        echo "SystemAudioVolume: '$sysAudVol_binary'"
        sudo nvram SystemAudioVolume=%80
        echo "SystemAudioVolume = '$(nvram SystemAudioVolume | cut -d$'\t' -f2 | xxd)'"
    fi
}

disable_osx_startup_chime 2>&1
