# Completions for tab-organize

complete -c tab-organize -f

# Subcommands
complete -c tab-organize -n '__fish_use_subcommand' -a windows -d 'List all windows with tab counts'
complete -c tab-organize -n '__fish_use_subcommand' -a plan -d 'Generate organization plan'
complete -c tab-organize -n '__fish_use_subcommand' -a execute -d 'Execute a plan file'

# Shared
complete -c tab-organize -s h -l help -d 'Show help'

# plan options
complete -c tab-organize -n '__fish_seen_subcommand_from plan' -l dry-run -d 'Print tab summary without calling AI'
complete -c tab-organize -n '__fish_seen_subcommand_from plan' -l goal -x -d 'Organizing goal'
function __tab_organize_windows
    set -l state "$HOME/Vaults/the-akashic-records/browser-sync/state.json"
    test -f $state; or return
    python3 -c '
import json, sys, collections
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
counts = collections.Counter()
titles = {}
for t in d.get("tabs", {}).values():
    w = t.get("windowId")
    if w is None: continue
    counts[w] += 1
    titles.setdefault(w, t.get("title") or "")
for w, n in counts.most_common():
    title = titles[w][:40].replace("\t", " ")
    print(f"{w}\t{n} tabs — {title}")
' $state 2>/dev/null
end

complete -c tab-organize -n '__fish_seen_subcommand_from plan' -l window -x -a '(__tab_organize_windows)' -d 'Only organize tabs in this window ID'

function __tab_organize_plans
    set -l dir "$HOME/Vaults/the-akashic-records/browser-sync/plans"
    test -d $dir; or return
    for f in $dir/*.md
        test -e $f; or continue
        set -l name (basename $f)
        set -l mtime (stat -f '%Sm' -t '%Y-%m-%d %H:%M' $f 2>/dev/null)
        printf '%s\t%s\n' $name $mtime
    end
end

# execute options
complete -c tab-organize -n '__fish_seen_subcommand_from execute' -l dry-run -d 'Print commands without sending to FIFO'
complete -c tab-organize -n '__fish_seen_subcommand_from execute' -f -a '(__tab_organize_plans)'
