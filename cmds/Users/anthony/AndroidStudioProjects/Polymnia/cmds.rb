module CMD
  def start(opts)
    opts.banner = "Usage: start"
    opts.info = "Build release APK, install, and launch Polymnia"
    lambda { |*args|
      EXE.bash %{
        ./gradlew installRelease --no-daemon && adb shell am start -n com.dayzerostudio.polymnia/.MainActivity
      }
    }
  end
  def logcat(opts)
    opts.banner = "Usage: logcat"
    opts.info = "Tail Android logcat for Polymnia"
    lambda { |*args|
      EXE.bash %{
        adb logcat --pid="$(adb shell pidof -s com.dayzerostudio.polymnia)"
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
