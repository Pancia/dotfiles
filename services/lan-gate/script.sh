#!/opt/homebrew/bin/fish

echo (date)": Starting lan-gate..."

# The macOS firewall dialog shows the executable's file name, so this copy of Python
# makes the dialog say lan-gate and gives the gate its own firewall rule. The copy is
# replaced by rename, never in place: macOS kills a signed binary that is overwritten.
set -l python_info (python3 -c 'import os, sys; print(os.path.realpath(sys.executable)); print(sys.base_prefix)')
set -l named_python ~/.local/share/named-python/lan-gate
mkdir -p (path dirname $named_python)
if not cmp -s $python_info[1] $named_python
    cp $python_info[1] $named_python.tmp
    and mv -f $named_python.tmp $named_python
end

# The copy lives outside Python's own folder, so it cannot find the standard library alone.
set -x PYTHONHOME $python_info[2]
proc-label lan-gate $named_python ~/dotfiles/services/lan-gate/gate.py
