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
    (cmus-remote "--pause"))) ;; toggles play/pause

(fn prev-track []
 (when (is-active?)
   (cmus-remote "--prev")
   (notify)))

(fn next-track []
 (when (is-active?)
   (cmus-remote "--next")
   (notify)))

(fn seek-forwards []
 (cmus-remote "--seek +10"))

(fn seek-backwards []
 (cmus-remote "--seek -10"))

(fn inc-volume []
  (when (and (is-active?) (is-playing?))
    (cmus-remote "--volume +5")))

(fn dec-volume []
  (when (and (is-active?) (is-playing?))
    (cmus-remote "--volume -5")))

(fn bind-media-keys []
  (hs.hotkey.bind {} "f7" prev-track)
  (hs.hotkey.bind {} "f8" play-or-pause)
  (hs.hotkey.bind {} "f9" next-track))

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
