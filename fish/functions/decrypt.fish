function decrypt --description 'Decrypt file'
    set -l output (string replace -r '\.enc$' '' "$argv[1]")
    openssl enc -d -aes-256-cbc -in "$argv[1]" > "$output"
end
