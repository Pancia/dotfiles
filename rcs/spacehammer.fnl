;;<[.spacehammer/config.fnl]>

(require-macros :lib.macros)
(local windows (require :windows))
(local slack (require :slack))
(local vim (require :vim))
(local cmus (require :cmus))
(local hermes (: (require :hermes) :start))

(local {:concat concat :logf logf} (require :lib.functional))

(fn activator [app-name]
  (fn activate []
    (windows.activate-app app-name)))

(fn toggle-console []
  (if-let [console (hs.console.hswindow)]
    (hs.closeConsole)
    (hs.openConsole)))

(local common-keys
  [{:mods [:ctrl]
    :key :space
    :action "lib.modal:toggle-modal"}
   {:key :tab
    :mods [:cmd :ctrl]
    :title "Hermes (fzf windows)"
    :action hermes.showOrNext}
   {:key :tab
    :mods [:cmd :ctrl :shift]
    :title "Hermes (fzf windows)"
    :action hermes.showOrPrev}
   {:mods [:alt]
    :key :tab
    :action "apps:next-app"}
   {:mods [:alt :shift]
    :key :tab
    :action "apps:prev-app"}])

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

(local nothing (fn []))

(fn empty [key]
  {:key key
   :repeatable true
   :timeout false
   :action nothing})

(local ignore-keys
  [:a :b :c :d :e :f :g :h :i :j :k :l :m
   :n :o :p :q :r :s :t :u :v :w :x :y :z
   "`" "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "-" "="
   "," "." "/" ";" "'" "[" "]" "\\"])

(fn without-remaining-keys [keybinds]
  (let [tbl {}]
    (each [i bind (ipairs keybinds)]
      (tset tbl (. bind :key) bind))
    (each [i letter (ipairs ignore-keys)]
      (if (not (. tbl letter))
        (tset tbl letter (empty letter))))
    (let [coll (icollect [k v (pairs tbl)] v)]
      (table.sort coll
        (fn [x y]
          (< (. x :key) (. y :key))))
      coll)))

(local media-bindings
  (without-remaining-keys
    [return
     {:key :c
      :title "Play or Pause"
      :action cmus.playOrPause}
     {:key :e
      :title "Edit Track"
      :action cmus.editTrack}
     {:key :y
      :title "Redownload from Youtube"
      :action cmus.ytdlTrack}
     {:key :a
      :title "Open Track in Audacity"
      :action cmus.openInAudacity}
     {:key :s
      :title "Select Track by Playlist"
      :action cmus.selectByPlaylist}
     {:key :t
      :title "Select Track by Tags"
      :action cmus.selectByTags}
     {:key :n
      :title "Next Track"
      :action cmus.nextTrack
      :repeatable true
      :timeout false}
     {:key :p
      :title "Prev Track"
      :action cmus.prevTrack
      :repeatable true
      :timeout false}
     {:key :l
      :title "Seek 10 Forwards"
      :action (cmus:seekForwards 10)
      :repeatable true
      :timeout false}
     {:key :h
      :title "Seek 10 Backwards"
      :action (cmus:seekBackwards 10)
      :repeatable true
      :timeout false}
     {:key "."
      :title "Seek 30 Forwards"
      :action (cmus:seekForwards 30)
      :repeatable true
      :timeout false}
     {:key ","
      :title "Seek 30 Backwards"
      :action (cmus:seekBackwards 30)
      :repeatable true
      :timeout false}
     {:key :j
      :title "Volume Down"
      :action cmus.decVolume
      :repeatable true
      :timeout false}
     {:key :k
      :title "Volume Up"
      :action cmus.incVolume
      :repeatable true
      :timeout false}]))

(fn record_audio_to_clipboard []
  (hs.execute "open-iterm-with pb-record" true))

(fn talk_to_ai [prompt]
  (fn []
    (hs.execute (.. "open-iterm-with ai-chat " prompt) true)))

(local ai-audio
  [
     {:key :.
      :title "Record audio to clipboard."
      :action record_audio_to_clipboard}
     {:key :/
      :title "Talk to chatGPT"
      :action (talk_to_ai "")}
     {:key :j
      :title "Journal with chatGPT"
      :action (talk_to_ai "reflective-journaling.txt")}
   ])

(local menu-items
  (without-remaining-keys
    [{:key :space
      :title "LaunchPad"
      :action (activator "LaunchPad")}
     {:key :a
      :title "Apps"
      :items app-bindings}
     {:key :f
      :title "Hermes (fzf windows)"
      :action hermes.show}
     {:key :m
      :title "Media"
      :items media-bindings
      :timeout false}
     {:key :w
      :title "Window"
      :items window-bindings}
     {:key :/
      :title "AI & Audio"
      :items ai-audio}
     ]))

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

(local apps
  [firefox-config
   hammerspoon-config])

(local config
  {:title "Main Menu"
   :items menu-items
   :keys common-keys
   :apps apps
   :hyper {:key :F18}})

config
