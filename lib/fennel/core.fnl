;; CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]

(local HOME (os.getenv "HOME"))

(local install (hs.loadSpoon "SpoonInstall"))
(tset install :use_syncinstall true)

(install:andUse "TextClipboardHistory"
  {:start true
   :hotkeys {:toggle_clipboard [["cmd" "ctrl"] "p"]}})

(install:andUse "FadeLogo"
  {:start true
   :config {:default_run 1.0}})

(local cmus (require :seeds.cmus))
(cmus.bind-media-keys)

(local homeboard (require :seeds.homeboard.core))
(when false
  (homeboard.start
    {:defaultDuration 180
     :homeBoardPath   (.. HOME "/Dropbox/HomeBoard/")
     :videosPath      (.. HOME "/Movies/HomeBoard")
     :todosPaths      {:dotfiles (.. HOME "/dotfiles/wiki/TODO.wiki")
                       :dropbox  (.. HOME "/Dropbox/wiki/Tasks.wiki")}}))

(local lotus (require :seeds.lotus.core))
(when false
  (lotus.start
    (let [notif-fn (fn [title]
                     (fn []
                       {: title
                        :withdrawAfter 0
                        :informativeText (homeboard.getLastPlan)
                        :subTitle (homeboard.getLastPlanTime)}))]
      {:sounds [{:name  "short"
                 :path  "bowl.wav"
                 :notif (notif-fn "Quick Stretch! #short")}
                {:name  "short"
                 :path  "bowl.wav"
                 :notif (notif-fn "Quick Stretch! #short")}
                {:name   "long"
                 :path   "gong.wav"
                 :volume .5
                 :notif  (notif-fn "Take a walk! #long")}]})))

(local watch (require :seeds.watch.core))
(when false
  (watch.start
    {:logDir  (.. (os.getenv "HOME") "/.log/watch/")
     :scripts [{:name "disable_osx_startup_chime"
                :command "~/dotfiles/misc/watch/disable_osx_startup_chime.watch.sh"
                :triggerEvery 60
                :delayStart 0}
               {:name "ytdl"
                :command "~/dotfiles/misc/watch/ytdl/ytdl.watch.sh"
                :triggerEvery 15
                :delayStart 5}
               {:name "extra"
                :command "~/dotfiles/misc/watch/extra.watch.sh"
                :triggerEvery (* 60 3)
                :delayStart 15}]}))

(local seeds {: lotus : homeboard : watch})

(local hs_global_modifier ["cmd" "ctrl"])
(hs.hotkey.bindSpec [hs_global_modifier "c"] hs.toggleConsole)
(hs.hotkey.bindSpec [hs_global_modifier "r"]
  (fn []
    (each [name seed (pairs seeds)]
      (when seed.stop
        (let [ok? (pcall #(seed:stop))]
          (when (not ok?)
            (hs.printf "\n\nERROR: stop(%s):\n\n" name)))))
    (hs.reload)))

(require :spacehammer.core)
