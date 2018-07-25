use github.com/zzamboni/elvish-modules/alias
alias:new .elvish exec elvish

fns_dir = ~/dotfiles/elvish/fns
put (ls $fns_dir) | each [file]{
    -source $fns_dir/$file
}
