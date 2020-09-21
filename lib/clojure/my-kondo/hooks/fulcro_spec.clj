(ns hooks.fulcro-spec
  (:require
    [clj-kondo.hooks-api :as api]))

(defn dbg [tag value]
  (prn tag (pr-str value) "->" (pr-str (api/sexpr value))) (prn)
  value)

(defn when-mocking* [children]
  (let [[mock-triples body] (split-with
                              (fn [part]
                                (some->> (second part)
                                  (= (api/token-node '=>))))
                              (partition-all 3 children))]
    {:node (api/list-node
             (list*
               (api/token-node 'with-redefs)
               (api/vector-node
                 (mapcat
                   (fn [[call _ value]]
                     [(api/token-node (first (:children call)))
                      (api/list-node
                        (list
                          (api/token-node 'fn)
                          (api/vector-node
                            (map (fn [param]
                                   (if (symbol? param) param '_))
                              (rest (:children call))))
                          value))])
                   mock-triples))
               (api/vector-node (map (comp #(api/list-node (list 'apply % [])) first :children first) mock-triples))
               (mapcat identity body)))}))

(defn provided [{{[_ _str & children] :children} :node}]
  (when-mocking* children))

(defn when-mocking [{{[_ & children] :children} :node}]
  (when-mocking* children))

(defn assertions [{{:keys [children]} :node}]
  {:node (api/list-node (list*
                          (api/token-node 'do)
                          (remove (comp '#{=> =fn=> =throws=> =check=>} api/sexpr)
                            children)))})
