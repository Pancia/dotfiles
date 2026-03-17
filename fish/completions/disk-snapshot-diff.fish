# Completions for disk-snapshot-diff

function __disk_snapshot_dates
    set -l dir ~/.local/share/disk-snapshots
    if test -d $dir
        for f in $dir/*.txt
            basename $f .txt
        end
    end
end

complete -c disk-snapshot-diff -f
complete -c disk-snapshot-diff -s t -d 'Minimum change in MB (default: 100)' -x
complete -c disk-snapshot-diff -s h -d 'Show usage'
complete -c disk-snapshot-diff -n 'test (count (commandline -opc)) -le 2' -a '(__disk_snapshot_dates)'
