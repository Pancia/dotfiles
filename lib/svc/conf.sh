# Shared by supervise, svc and svc-tmux: which config files a project has, in
# the order to source them -
#   ./.svc.conf                                   project, committed
#   $SVC_FS_CONFIG/<project path>/svc.conf        private vault (default below),
#                                                 logical path first, then physical
#   ./.svc.local.conf                             git-ignored local overrides
# The vault tree is the one `cmds` uses for private cmds.rb files, so a project's
# svc.conf sits next to its cmds.rb. Logical-then-physical is cmds' order too.
#
# It only PRINTS the paths; each caller sources them at top level:
#   while IFS= read -r _cf; do . "$_cf"; done < <(svc_conf_files)
# Sourcing inside a function would make every `declare` in a config local to it
# (and bash 3.2 has no `declare -g`), silently dropping those variables.
svc_conf_files() {
  local root="${SVC_FS_CONFIG:-$HOME/Vaults/work-config/fs-config}" p
  [ -r .svc.conf ] && echo "./.svc.conf"
  for p in "$PWD" "$(pwd -P)"; do
    if [ -r "$root$p/svc.conf" ]; then echo "$root$p/svc.conf"; break; fi
  done
  [ -r .svc.local.conf ] && echo "./.svc.local.conf"
  return 0
}
# For messages: where config was looked for.
svc_conf_where() {
  echo ".svc.conf, ${SVC_FS_CONFIG:-$HOME/Vaults/work-config/fs-config}$PWD/svc.conf or .svc.local.conf"
}
