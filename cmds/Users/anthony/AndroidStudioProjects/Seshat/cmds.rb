module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Build debug APK, install, and launch Seshat"
    lambda { |*args|
      EXE.bash %{
        ./gradlew installDebug --no-daemon && adb shell am start -n com.dayzerostudio.seshat/.MainActivity
      }
    }
  end
  def logcat(opts)
    opts.banner = "Usage: logcat"
    opts.info = "Tail Android logcat for Seshat"
    lambda { |*args|
      EXE.bash %{
        adb logcat --pid="$(adb shell pidof -s com.dayzerostudio.seshat)"
      }
    }
  end
  def shell(opts)
    opts.banner = "Usage: shell [args...]"
    opts.info = "Open adb shell as Seshat app user"
    lambda { |*args|
      EXE.bash %{
        adb shell run-as com.dayzerostudio.seshat #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
