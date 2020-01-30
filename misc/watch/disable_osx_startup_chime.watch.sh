function disable_osx_startup_chime() {
    local sysAudVol=$(nvram SystemAudioVolume | cut -d$'\t' -f2)
    local logDir=~/.log/disable_osx_startup_chime
    mkdir -p $logDir
    if [[ ! "$sysAudVol" == '%80' ]]; then
        local sysAudVol_binary="$(echo ${sysAudVol} | xxd)"
        echo "$(date '+%x %X') -> $sysAudVol_binary" >> $logDir/log
        #TODO: add to sudoers on install ? with args?
        #   $(whoami) ALL=(ALL) NOPASSWD: /usr/sbin/nvram
        echo "SystemAudioVolume = '$sysAudVol_binary'"
        sudo nvram SystemAudioVolume=%80
        exit 80
    fi
}

disable_osx_startup_chime
