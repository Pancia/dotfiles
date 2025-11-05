# Encryption/decryption helpers
function encrypt --description 'Encrypt file with AES-256-CBC'
    openssl enc -aes-256-cbc -salt -in "$argv[1]" -out "$argv[1].enc"
end

function decrypt --description 'Decrypt file'
    set -l output (string replace -r '\.enc$' '' "$argv[1]")
    openssl enc -d -aes-256-cbc -in "$argv[1]" > "$output"
end
