#!/opt/homebrew/bin/fish

echo (date)": Starting lakshmi content server on port 8420..."
cd ~/projects/lakshmi/public

# The macOS firewall dialog shows the executable's file name, and proc-label only
# changes argv[0]. A copy of Python under this service's name gives the dialog a
# useful name and gives Lakshmi its own firewall rule at a path that stays the same
# when the Python version changes. The copy is replaced by rename, never in place:
# macOS kills a signed binary that is overwritten.
set -l python_info (python3 -c 'import os, sys; print(os.path.realpath(sys.executable)); print(sys.base_prefix)')
set -l named_python ~/.local/share/named-python/lakshmi-server
mkdir -p (path dirname $named_python)
if not cmp -s $python_info[1] $named_python
    cp $python_info[1] $named_python.tmp
    and mv -f $named_python.tmp $named_python
end

# The copy lives outside Python's own folder, so it cannot find the standard library alone.
set -x PYTHONHOME $python_info[2]
proc-label lakshmi $named_python ~/dotfiles/services/lakshmi/serve.py
