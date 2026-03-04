module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Run main.py via uv"
    lambda { |*args|
      EXE.bash %{
        uv sync && uv run --with setproctitle proc-label asmr-board python main.py
      }
    }
  end

  def pid(opts)
    opts.banner = "Usage: pid"
    opts.info = "Print the running app's PID"
    lambda { |*args|
      EXE.bash %{
        cat /tmp/asmr-board.pid
      }
    }
  end

  def uidump(opts)
    opts.banner = "Usage: uidump"
    opts.info = "Dump UI state (window, tracks, volumes) via SIGWINCH"
    lambda { |*args|
      EXE.bash %{
        kill -WINCH $(cat /tmp/asmr-board.pid) && sleep 0.3 && cat /tmp/asmr-board-uidump.txt
      }
    }
  end

  def memdump(opts)
    opts.banner = "Usage: memdump"
    opts.info = "Dump memory stats (RSS, GC, top allocations) via SIGUSR1"
    lambda { |*args|
      EXE.bash %{
        PID=$(cat /tmp/asmr-board.pid) && kill -USR1 $PID && sleep 0.3 && cat /tmp/asmr-board-memdump-$PID.txt
      }
    }
  end

  def repl(opts)
    opts.banner = "Usage: repl"
    opts.info = "Open manhole REPL inside the running app via SIGUSR2"
    lambda { |*args|
      EXE.bash %{
        PID=$(cat /tmp/asmr-board.pid) && kill -USR2 $PID && manhole-cli $PID
      }
    }
  end

  def log(opts)
    opts.banner = "Usage: log"
    opts.info = "Tail the app log file"
    lambda { |*args|
      EXE.bash %{
        tail -f /tmp/asmr-board-$(cat /tmp/asmr-board.pid).log
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
