(ns tee.kaocha-plugins
  (:require
    [clojure.java.io :as io]
    [kaocha.plugin :as p]
    [nrepl.core :as nrepl]))

(defn forward-to-nrepl-tap [x]
  (when-let [nrepl-port (when (.exists (io/file ".nrepl-port"))
                          (some-> (slurp ".nrepl-port") Integer/parseInt))]
    (with-open [conn (nrepl/connect :port nrepl-port)]
      (nrepl/message (nrepl/client conn 1000)
        {:op "tap>" :value (pr-str x)}))))

(p/defplugin tee.kaocha-plugins/forward-taps-to-nrepl-plugin
  (pre-run [config]
    (add-tap forward-to-nrepl-tap)
    config)
  (post-run [test-result]
    (remove-tap forward-to-nrepl-tap)
    test-result)
  (pre-report [report]
    (when (#{:fail :error} (:type report))
      (forward-to-nrepl-tap
        {:tee/test-report (dissoc report :kaocha/test-plan :kaocha/testable)
         :kaocha.testable/id (get-in report [:kaocha/testable :kaocha.testable/id])}))
    report))
