(local homeboard (require :seeds.homeboard.init))

(fn start [config]
  (homeboard:start config))

(fn stop []
  (homeboard:stop))

{: start
 : stop}
