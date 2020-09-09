(ns hooks.fulcro-spec
  (:require
    [clj-kondo.hooks-api :as api]))

(defn dbg [tag value]
  (prn tag (api/sexpr value)) (prn)
  value)

(defn when-mocking* [children]
  (let [mock-triples (partition 3 (butlast children))
        body (last children)]
    {:node (api/list-node
             (list
               (api/token-node 'with-redefs)
               (api/vector-node
                 (mapcat
                   (fn [[call _ value]]
                     [(api/token-node (first (:children call)))
                      (api/list-node
                        (list
                          (api/token-node 'fn)
                          (api/vector-node (rest (:children call)))
                          value))])
                   mock-triples))
               body))}))

(defn provided [{{[_ _str & children] :children} :node}]
  (when-mocking* children))

(defn when-mocking [{{[_ & children] :children} :node}]
  (when-mocking* children))

(comment
  (fulcro-spec.core/when-mocking
    (f a b & x) => (some-value)
    body)
  ;; should become
  (with-redefs
    [f (fn [a b & x] (some-value))]
    body)
  )
