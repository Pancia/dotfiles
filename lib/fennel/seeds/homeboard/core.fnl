(local homeboard (require :seeds.homeboard.init))

(fn start [config]
  (homeboard:start config))

(fn stop []
  (homeboard:stop))

(fn getLastPlan []
  (homeboard:getLastPlan))

(fn getLastPlanTime []
  (homeboard:getLastPlanTime))

{: start
 : stop
 : getLastPlanTime
 : getLastPlan}
