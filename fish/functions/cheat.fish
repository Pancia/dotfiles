function cheat --description 'Use cht.sh for quick reference'
    if not command -v cht.sh &> /dev/null
        curl https://cht.sh/:cht.sh > /usr/local/bin/cht.sh
        chmod +x /usr/local/bin/cht.sh
    end
    cht.sh $argv
end
