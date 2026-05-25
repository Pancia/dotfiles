module CMD
  def build(opts)
    opts.banner = "Usage: build"
    opts.info = "Build Sanctuary app (Debug)"
    lambda { |*args|
      EXE.bash %{ just build }
    }
  end
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Build and launch Sanctuary app"
    lambda { |*args|
      EXE.bash %{ just run }
    }
  end
  def deps(opts)
    opts.banner = "Usage: deps"
    opts.info = "Resolve SPM package dependencies"
    lambda { |*args|
      EXE.bash %{ just deps }
    }
  end
  def generate(opts)
    opts.banner = "Usage: generate"
    opts.info = "Regenerate Xcode project from project.yml"
    lambda { |*args|
      EXE.bash %{ just generate }
    }
  end
  def kill(opts)
    opts.banner = "Usage: kill"
    opts.info = "Force-kill Sanctuary (escape stuck kiosk)"
    lambda { |*args|
      EXE.bash %{ just kill }
    }
  end
  def dev_timer(opts)
    opts.banner = "Usage: dev_timer"
    opts.info = "Dev: boot into .active with a 10-second timer"
    lambda { |*args|
      EXE.bash %{ just dev-timer }
    }
  end
  def dev_gate(opts)
    opts.banner = "Usage: dev_gate"
    opts.info = "Dev: boot to morning gate"
    lambda { |*args|
      EXE.bash %{ just dev-gate }
    }
  end
  def dev_map(opts)
    opts.banner = "Usage: dev_map"
    opts.info = "Dev: boot directly to kingdom map"
    lambda { |*args|
      EXE.bash %{ just dev-map }
    }
  end
  def dev_briefing(opts)
    opts.banner = "Usage: dev_briefing"
    opts.info = "Dev: boot to briefing screen with stub text (skips Claude)"
    lambda { |*args|
      EXE.bash %{ just dev-briefing }
    }
  end
  def dev_grove(opts)
    opts.banner = "Usage: dev_grove"
    opts.info = "Dev: boot to grove detail (first seed grove, or SANCTUARY_GROVE_ID)"
    lambda { |*args|
      EXE.bash %{ just dev-grove }
    }
  end
  def dev_clearing(opts)
    opts.banner = "Usage: dev_clearing"
    opts.info = "Dev: boot to clearing view after a short session"
    lambda { |*args|
      EXE.bash %{ just dev-clearing }
    }
  end
  def dev_hearth(opts)
    opts.banner = "Usage: dev_hearth"
    opts.info = "Dev: boot to hearth fire with a mock day's activity"
    lambda { |*args|
      EXE.bash %{ just dev-hearth }
    }
  end
  def dev_rest(opts)
    opts.banner = "Usage: dev_rest"
    opts.info = "Dev: boot to the rest screen"
    lambda { |*args|
      EXE.bash %{ just dev-rest }
    }
  end
  def dev_reset(opts)
    opts.banner = "Usage: dev_reset"
    opts.info = "Dev: wipe ~/.local/state/sanctuary-dev"
    lambda { |*args|
      EXE.bash %{ just dev-reset }
    }
  end
end

trap "SIGINT" do
  exit 130
end
