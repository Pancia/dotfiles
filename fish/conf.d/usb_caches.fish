# Redirect large tool caches to USB stick when mounted
set -l usb /Volumes/vansuny128/caches

if test -d /Volumes/vansuny128
    set -gx GRADLE_USER_HOME $usb/gradle
    set -gx HF_HOME $usb/huggingface
set -gx PUB_CACHE $usb/pub
    set -gx TORCH_HOME $usb/torch
    set -gx MAVEN_OPTS "-Dmaven.repo.local=$usb/m2/repository $MAVEN_OPTS"
end
