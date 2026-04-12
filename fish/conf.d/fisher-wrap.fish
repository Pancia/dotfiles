status is-interactive
or exit 0

if functions -q fisher; and not functions -q _fisher_orig
    functions --copy fisher _fisher_orig

    function fisher --description 'wrapper: intercept update to restore local patches'
        if test "$argv[1]" = update
            fisher-up $argv[2..-1]
        else
            _fisher_orig $argv
        end
    end
end
