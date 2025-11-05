function heater --description 'CPU stress test to monitor temperature'
    # Start background yes processes
    yes > /dev/null &
    set -l pid1 $last_pid
    yes > /dev/null &
    set -l pid2 $last_pid
    yes > /dev/null &
    set -l pid3 $last_pid

    # Monitor temperatures
    sudo powermetrics --samplers smc | ag '(CPU.*temp|Fan)'

    # Cleanup
    kill $pid1 $pid2 $pid3 2>/dev/null
end
