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
end

trap "SIGINT" do
  exit 130
end
