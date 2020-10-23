(local watch (require :seeds.watch.init))

(fn start [config]
  (watch:start config))

(fn stop []
  (watch:stop))

{: start
 : stop}
