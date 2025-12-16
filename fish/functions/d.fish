# Directory bookmark system
function d --description 'Navigate to bookmarked directory'
    if test (count $argv) -eq 1
        set -l bookmark_dir ~/.config/d
        set -l exact_match "$bookmark_dir/$argv[1]"

        if test -f $exact_match
            cd (cat $exact_match)
        else
            # Use fzf to complete from matching bookmarks
            set -l selected (ls -1 $bookmark_dir | fzf --query="$argv[1]" --select-1 --exit-0)
            if test -n "$selected"
                cd (cat "$bookmark_dir/$selected")
            end
        end
    else if test (count $argv) -eq 0
        # No args - show all with fzf
        set -l selected (ls -1 ~/.config/d | fzf)
        if test -n "$selected"
            cd (cat ~/.config/d/$selected)
        end
    else
        cd (ruby ~/dotfiles/lib/ruby/d.rb getbookmark $argv)
    end
end

function d! --description 'Set directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb setbookmark $argv
end

function de --description 'Edit directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb editbookmark $argv
end

function d_ --description 'Delete directory bookmark'
    ruby ~/dotfiles/lib/ruby/d.rb delbookmark $argv
end

function __d --description 'Direct d.rb access'
    ruby ~/dotfiles/lib/ruby/d.rb $argv
end

# Export bookmarks
for p in (ruby ~/dotfiles/lib/ruby/d.rb export)
    set -l parts (string split '=' -- $p)
    set -gx $parts[1] $parts[2]
end
