function encrypt {
    openssl enc -aes-256-cbc -salt -in "$1" -out "$1.enc"
}

function decrypt {
    openssl enc -d -aes-256-cbc -in "$1" > "${1:r}"
}
