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
    (cmus-remote "--pause")))

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

{:play-or-pause play-or-pause
 :prev-track prev-track
 :next-track next-track
 :seek-forwards seek-forwards
 :seek-backwards seek-backwards
 :inc-volume inc-volume
 :dec-volume dec-volume}
