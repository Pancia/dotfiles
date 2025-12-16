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
        uv run flet build apk --project "Lakshmi"
      }
    }
  end
  def deploy(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        adb install build/apk/app-release.apk
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
end

trap "SIGINT" do
  exit 130
end
