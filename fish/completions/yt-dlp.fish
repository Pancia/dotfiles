# Dynamic format completions from -F output
# Extends vendor completions at /opt/homebrew/share/fish/vendor_completions.d/yt-dlp.fish

function __yt_dlp_format_completions
    # Find URL in command line
    set -l tokens (commandline -opc)
    for token in $tokens
        if string match -qr '^https?://' -- $token
            # Cache results for 5 minutes per URL
            set -l cache_file /tmp/yt-dlp-formats-(echo $token | md5)
            if not test -f $cache_file; or test (math (date +%s) - (stat -f%m $cache_file)) -gt 300
                yt-dlp -F --no-warnings "$token" 2>/dev/null | \
                    awk 'NR>3 && /^[0-9a-z]+/ {
                        id=$1; $1=""; desc=substr($0,2);
                        gsub(/  +/, " ", desc);
                        print id"\t"desc
                    }' > $cache_file
            end
            cat $cache_file
            return
        end
    end
end

complete -c yt-dlp -s f -l format -xa '(__yt_dlp_format_completions)'
