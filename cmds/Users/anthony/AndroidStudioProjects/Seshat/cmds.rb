module CMD
  def start(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        ./gradlew installDebug --no-daemon && adb shell am start -n com.dayzerostudio.seshat/.MainActivity
      }
    }
  end
  def logcat(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        adb logcat --pid="$(adb shell pidof -s com.dayzerostudio.seshat)"
      }
    }
  end
  def shell(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        adb shell run-as com.dayzerostudio.seshat #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
