;;<[.spacehammer/config.fnl]>

(require-macros :lib.macros)
(local windows (require :windows))
(local slack (require :slack))
(local vim (require :vim))
(local cmus (require :cmus))

(local {:concat concat :logf logf} (require :lib.functional))

(fn activator [app-name]
  (fn activate []
    (windows.activate-app app-name)))

(fn toggle-console []
  (if-let [console (hs.console.hswindow)]
   (hs.closeConsole)
   (hs.openConsole)))

(local return
       {:key :space
        :title "Back"
        :action :previous})

(local window-jumps
       [{:mods [:cmd]
         :key "hjkl"
         :title "Jump"}
        {:mods [:cmd]
         :key :h
         :action "windows:jump-window-left"
         :repeatable true}
        {:mods [:cmd]
         :key :j
         :action "windows:jump-window-above"
         :repeatable true}
        {:mods [:cmd]
         :key :k
         :action "windows:jump-window-below"
         :repeatable true}
        {:mods [:cmd]
         :key :l
         :action "windows:jump-window-right"
         :repeatable true}])

(local window-halves
       [{:key "hjkl"
         :title "Halves"}
        {:key :h
         :action "windows:resize-half-left"
         :repeatable true}
        {:key :j
         :action "windows:resize-half-bottom"
         :repeatable true}
        {:key :k
         :action "windows:resize-half-top"
         :repeatable true}
        {:key :l
         :action "windows:resize-half-right"
         :repeatable true}])

(local window-increments
       [{:mods [:alt]
         :key "hjkl"
         :title "Increments"}
        {:mods [:alt]
         :key :h
         :action "windows:resize-inc-left"
         :repeatable true}
        {:mods [:alt]
         :key :j
         :action "windows:resize-inc-bottom"
         :repeatable true}
        {:mods [:alt]
         :key :k
         :action "windows:resize-inc-top"
         :repeatable true}
        {:mods [:alt]
         :key :l
         :action "windows:resize-inc-right"
         :repeatable true}])

(local window-resize
       [{:mods [:shift]
         :key "hjkl"
         :title "Resize"}
        {:mods [:shift]
         :key :h
         :action "windows:resize-left"
         :repeatable true}
        {:mods [:shift]
         :key :j
         :action "windows:resize-down"
         :repeatable true}
        {:mods [:shift]
         :key :k
         :action "windows:resize-up"
         :repeatable true}
        {:mods [:shift]
         :key :l
         :action "windows:resize-right"
         :repeatable true}])

(local window-move-screens
       [{:key "n, p"
         :title "Move next\\previous screen"}
        {:mods [:shift]
         :key "n, p"
         :title "Move up\\down screens"}
        {:key :n
         :action "windows:move-south"
         :repeatable true}
        {:key :p
         :action "windows:move-north"
         :repeatable true}
        {:mods [:shift]
         :key :n
         :action "windows:move-west"
         :repeatable true}
        {:mods [:shift]
         :key :p
         :action "windows:move-east"
         :repeatable true}])

(local window-bindings
       (concat
        [return
         {:key :w
          :title "Last Window"
          :action "windows:jump-to-last-window"}]
        window-jumps
        window-halves
        window-increments
        window-resize
        window-move-screens
        [{:key :m
          :title "Maximize"
          :action "windows:maximize-window-frame"}
         {:key :c
          :title "Center"
          :action "windows:center-window-frame"}
         {:key :g
          :title "Grid"
          :action "windows:show-grid"}
         {:key :u
          :title "Undo"
          :action "windows:undo-action"}]))

(local app-bindings
       [return
        {:key :g
         :action (activator "Google Chrome")}
        {:key :f
         :title "Firefox"
         :action (activator "Firefox")}
        {:key :i
         :title "iTerm"
         :action (activator "iTerm2")}
        {:key :s
         :title "Slack"
         :action (activator "Slack")}])

(local media-bindings
       [return
        {:key :s
         :title "Play or Pause"
         :action cmus.play-or-pause}
        {:key :p
         :title "Prev Track"
         :action cmus.prev-track
         :repeatable true
         :timeout false}
        {:key :n
         :title "Next Track"
         :action cmus.next-track
         :repeatable true
         :timeout false}
        {:key :l
         :title "Seek Forwards"
         :action cmus.seek-forwards
         :repeatable true
         :timeout false}
        {:key :h
         :title "Seek Backwards"
         :action cmus.seek-backwards
         :repeatable true
         :timeout false}
        {:key :j
         :title "Volume Down"
         :action cmus.dec-volume
         :repeatable true
         :timeout false}
        {:key :k
         :title "Volume Up"
         :action cmus.inc-volume
         :repeatable true
         :timeout false}])

(local menu-items
       [{:key :space
         :title "LaunchPad"
         :action (activator "LaunchPad")}
        {:key :w
         :title "Window"
         :items window-bindings}
        {:key :a
         :title "Apps"
         :items app-bindings}
        {:key :j
         :title "Jump"
         :action "windows:jump"}
        {:key :m
         :title "Media"
         :items media-bindings
         :timeout false}])

(local common-keys
       [{:mods [:cmd]
         :key :space
         :action "lib.modal:activate-modal"}
        {:mods [:alt]
         :key :n
         :action "apps:next-app"}
        {:mods [:alt]
         :key :p
         :action "apps:prev-app"}
        {:mods [:cmd :ctrl]
         :key "`"
         :action toggle-console}])

(local browser-keys
       [{:mods [:cmd :shift]
         :key :l
         :action "chrome:open-location"}
        {:mods [:alt]
         :key :k
         :action "chrome:next-tab"
         :repeat true}
        {:mods [:alt]
         :key :j
         :action "chrome:prev-tab"
         :repeat true}])

(local browser-items menu-items)

(local chrome-config
       {:key "Google Chrome"
        :keys browser-keys
        :items browser-items})

(local firefox-config
       {:key "Firefox"
        :keys browser-keys
        :items browser-items})

(local hammerspoon-config
       {:key "Hammerspoon"
        :items (concat
                menu-items
                [{:key :r
                  :title "Reload Console"
                  :action hs.reload}
                 {:key :c
                  :title "Clear Console"
                  :action hs.console.clearConsole}])
        :keys []})

(local slack-config
       {:key "Slack"
        :keys [{:mods [:cmd]
                :key  :g
                :action "slack:scroll-to-bottom"}
               {:mods [:ctrl]
                :key :r
                :action "slack:add-reaction"}
               {:mods [:ctrl]
                :key :h
                :action "slack:prev-element"}
               {:mods [:ctrl]
                :key :l
                :action "slack:next-element"}
               {:mods [:ctrl]
                :key :t
                :action "slack:thread"}
               {:mods [:ctrl]
                :key :p
                :action "slack:prev-day"}
               {:mods [:ctrl]
                :key :n
                :action "slack:next-day"}
               {:mods [:ctrl]
                :key :e
                :action "slack:scroll-up"
                :repeat true}
               {:mods [:ctrl]
                :key :y
                :action "slack:scroll-down"
                :repeat true}
               {:mods [:ctrl]
                :key :i
                :action "slack:next-history"
                :repeat true}
               {:mods [:ctrl]
                :key :o
                :action "slack:prev-history"
                :repeat true}
               {:mods [:ctrl]
                :key :j
                :action "slack:down"
                :repeat true}
               {:mods [:ctrl]
                :key :k
                :action "slack:up"
                :repeat true}]})

(local apps
       [chrome-config
        firefox-config
        hammerspoon-config
        slack-config])

(local config
       {:title "Main Menu"
        :items menu-items
        :keys common-keys
        :apps apps
        :hyper {:key :F18}})

config
