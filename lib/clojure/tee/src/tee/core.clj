(ns tee.core
  (:require
    [nrepl.middleware :refer [set-descriptor!]])
  (:import
    [nrepl.transport Transport]))

(defn is-user-eval? [{:keys [op file code]}]
  (and file (= op "eval")
    (not (.startsWith code "(do {:conjure-highlight/silent true}"))))

(defn tee-transport [{:as msg :keys [transport]}]
  (assoc msg :transport
    (reify Transport
      (recv [_] (.recv transport))
      (recv [_ timeout] (.recv transport timeout))
      (send [this response]
        (try
          (when (is-user-eval? msg)
            (when-let [out (:out response)]
              (.print System/out out))
            (when-let [err (:err response)]
              (.print System/out err))
            (when-let [value (:value response)]
              (.println System/out (pr-str value))
              (.print System/out (str (ns-name *ns*) "=> "))))
          (catch Throwable _))
        (try
          (.send transport response)
          (catch Throwable _))
        this))))

(defn middleware [h]
  (fn [msg]
    (when (is-user-eval? msg)
      (.println System/out (:code msg)))
    (h (tee-transport msg))))

(set-descriptor! #'middleware
  ;; expects: below / after
  {:expects #{"eval"}})
