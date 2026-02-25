module CMD
  def start(opts)
    opts.banner = "Usage: start [args...]"
    opts.info = "Run Flet app on port 8555"
    lambda { |*args|
      EXE.bash %{
        uv run flet run --recursive --port 8555 #{args.join " "}
      }
    }
  end
  def build(opts)
    opts.banner = "Usage: build"
    opts.info = "Build Lakshmi APK with deep linking"
    lambda { |*args|
      EXE.bash %{
        uv run flet build apk --deep-linking-scheme=lakshmi --deep-linking-host=app --project "Lakshmi"
      }
    }
  end
  def deploy(opts)
    opts.banner = "Usage: deploy"
    opts.info = "Uninstall and reinstall APK on device"
    lambda { |*args|
      EXE.bash %{
        adb uninstall com.flet.lakshmi; adb install build/apk/app-release.apk
      }
    }
  end
  def logcat(opts)
    opts.banner = "Usage: logcat"
    opts.info = "Tail Android logcat for Lakshmi"
    lambda { |*args|
      EXE.bash %{
        adb logcat --pid="$(adb shell pidof -s com.flet.lakshmi)"
      }
    }
  end

  def install(opts)
    opts.banner = "Usage: install"
    opts.info = "Install Flet with all extras via uv"
    lambda { |*args|
      EXE.bash %{
          uv pip install "flet[all]"
      }
    }
  end

  def engage(opts)
    opts.banner = "Usage: engage"
    opts.info = "Build, deploy, and launch rituals deep link"
    lambda { |*args|
      EXE.bash %{
          cmds build && cmds deploy && adb shell am start -a android.intent.action.VIEW -d "lakshmi://app/rituals"
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
