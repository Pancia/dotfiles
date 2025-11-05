function reset --description 'Clear terminal scrollback'
    printf '\e]1337;ClearScrollback\a'
end
