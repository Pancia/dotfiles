#!/usr/bin/env fish

function sysAudVol
    nvram SystemAudioVolume | cut -f2
end

function disable_osx_startup_chime
    echo (date '+%x %X')
    set -l vol (sysAudVol | xxd)
    echo "SystemAudioVolume is: '$vol'"
    if test (sysAudVol) != '%80'
        sudo nvram SystemAudioVolume=%80
        set -l vol (sysAudVol | xxd)
        echo "SystemAudioVolume set to: '$vol'"
    end
    echo
end

disable_osx_startup_chime 2>&1
