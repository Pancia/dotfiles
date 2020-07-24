(ns utils.core
  (:require
    [clojure.java.io :as io]
    [clojure.tools.namespace.file :as ns-file]
    [clojure.tools.namespace.track :as ns-track]
    [clojure.tools.namespace.find :as ns-find]
    [com.gfredericks.dot-slash-2 :as dot-slash-2]))

(def dep-graph (::ns-track/deps
                 (ns-file/add-files {}
                   (ns-find/find-sources-in-dir
                     (io/file "src") ns-find/clj))))

(defn paths-to-ns
  ([start-ns target-ns] (paths-to-ns start-ns target-ns []))
  ([current-ns target-ns path]
   (let [deps (get (:dependencies dep-graph) current-ns)
         path (conj path current-ns)]
     (cond-> (filterv seq
               (mapcat #(paths-to-ns % target-ns path)
                 deps))
       (contains? deps target-ns)
       (conj (conj path target-ns))))))

(dot-slash-2/!
 '{. [clojure.repl/doc
      clojure.repl/source]
   .ns [utils.core/paths-to-ns]})

(prn ::INITIALIZED)
