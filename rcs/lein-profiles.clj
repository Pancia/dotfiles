;[.lein/profiles.clj]
{:user {:plugins [[cider/cider-nrepl "0.12.0"]
                  [lein-ancient "0.6.8"]
                  [lein-bikeshed "0.2.0"]
                  [lein-kibit "0.1.2"]
                  [lein-localrepo  "0.5.3"]
                  [lein-pprint "1.1.1"]]

        :repl-options {:timeout 120000}

        :dependencies [[cljfmt "0.3.0"]
                       [repetition-hunter "1.0.0"]]}}
