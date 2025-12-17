module CMD
  def start(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        uv run flet run --recursive --port 8555 #{args.join " "}
      }
    }
  end
  def build(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        uv run flet build apk --deep-linking-scheme=lakshmi --deep-linking-host=app --project "Lakshmi"
      }
    }
  end
  def deploy(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        adb uninstall com.flet.lakshmi; adb install build/apk/app-release.apk
      }
    }
  end
  def logcat(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        adb logcat --pid="$(adb shell pidof -s com.flet.lakshmi)"
      }
    }
  end

  def install(opts)
    opts.banner = "Usage: install FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
          uv pip install "flet[all]"
      }
    }
  end

  def engage(opts)
    opts.banner = "Usage: engage FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
          cmds build && cmds deploy && adb shell am start -a android.intent.action.VIEW -d "lakshmi://app/rituals"
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
