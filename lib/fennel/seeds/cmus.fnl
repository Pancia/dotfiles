(local cmus-path "/usr/local/bin/")

(fn cmus-remote [action]
  (hs.execute (.. cmus-path "/cmus-remote " action)))

(fn is-active? []
  (let [(_ status) (hs.execute (.. cmus-path "/cmus-remote --raw status"))]
    status))

(fn is-playing? []
  (let [cmus-status (hs.execute (.. cmus-path "/cmus-remote --raw status"))]
    (string.match cmus-status "status playing")))

(fn notify []
  (let [(res status) (cmus-remote "--raw status")]
    (when status
      (let [artist (string.match res "tag artist ([^\n]+)")
            album (string.match res "tag album ([^\n]+)")
            title (string.match res "tag title ([^\n]+)")]
        (hs.notify.show title artist album)))))

(fn play-or-pause []
  (when (is-active?)
    ;; NOTE: --pause toggles play/pause
    (cmus-remote "--pause")))

(fn prev-track []
 (when (is-active?)
   (cmus-remote "--prev")
   (notify)))

(fn next-track []
 (when (is-active?)
   (cmus-remote "--next")
   (notify)))

(fn seek-forwards [num]
 (lambda [] (cmus-remote (.. "--seek +" num))))

(fn seek-backwards [num]
 (lambda [] (cmus-remote (.. "--seek -" num))))

(fn inc-osx-volume []
  (let [output (hs.audiodevice.defaultOutputDevice)]
    (output:setVolume (+ (output:volume) (/ 100 15)))
    (: (hs.sound.getByName "Pop") :play)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" true) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" false) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" true) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" false) :post)
    ))

(fn dec-osx-volume []
  (let [output (hs.audiodevice.defaultOutputDevice)]
    (output:setVolume (- (output:volume) (/ 100 15)))
    (: (hs.sound.getByName "Pop") :play)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" true) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" false) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" true) :post)
    (: (hs.eventtap.event.newSystemKeyEvent "MUTE" false) :post)))

(fn inc-volume []
  (if (and (is-active?) (is-playing?))
    (cmus-remote "--volume +5")
    (inc-osx-volume)))

(fn dec-volume []
  (if (and (is-active?) (is-playing?))
    (cmus-remote "--volume -5")
    (dec-osx-volume)))

(fn raw-osx-dec-volume []
  (print :raw-dec)
  (: (hs.eventtap.event.newSystemKeyEvent "SOUND_DOWN" true) :post)
  (: (hs.eventtap.event.newSystemKeyEvent "SOUND_DOWN" false) :post))

(fn raw-osx-inc-volume []
  (print :raw-inc)
  (: (hs.eventtap.event.newSystemKeyEvent "SOUND_UP" true) :post)
  (: (hs.eventtap.event.newSystemKeyEvent "SOUND_UP" false) :post))

(fn bind-media-keys []
  (hs.hotkey.bind {} "f7" prev-track)
  (hs.hotkey.bind {} "f8" play-or-pause)
  (hs.hotkey.bind {} "f9" next-track)
  (if false
    (do
      (hs.hotkey.bind {} "f13" dec-volume)
      (hs.hotkey.bind {} "f14" inc-volume)
      (hs.hotkey.bind "cmd" "f13" dec-osx-volume)
      (hs.hotkey.bind "cmd" "f14" inc-osx-volume))
    (do
      (hs.hotkey.bind {} "f13" raw-osx-dec-volume)
      (hs.hotkey.bind {} "f14" raw-osx-inc-volume))))

(fn edit-track []
  (when (and (is-active?) (is-playing?))
    (hs.execute "cmedit" true)))

(fn select-by-playlist []
  (when (is-active?)
    (hs.execute "cmselect" true)))

(fn select-by-tags []
  (when (is-active?)
    (hs.execute "cmselect --filter-by-tags" true)))

{: play-or-pause
 : prev-track
 : next-track
 : seek-forwards
 : seek-backwards
 : inc-volume
 : dec-volume
 : bind-media-keys
 : edit-track
 : select-by-playlist
 : select-by-tags}
