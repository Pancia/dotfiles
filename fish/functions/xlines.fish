function xlines
    set file $argv[1]
    set cmd $argv[2..-1]
    while read -l line
        set expanded (string replace -a -- '{}' $line $cmd)
        $expanded
    end < $file
end
