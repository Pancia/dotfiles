function encrypt --description 'Encrypt file with AES-256-CBC'
    openssl enc -aes-256-cbc -salt -in "$argv[1]" -out "$argv[1].enc"
end
