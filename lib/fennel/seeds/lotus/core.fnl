(local lotus (require :seeds.lotus.init))

(fn start [config]
  (lotus:start config))

(fn stop []
  (lotus:stop))

{: start
 : stop}
