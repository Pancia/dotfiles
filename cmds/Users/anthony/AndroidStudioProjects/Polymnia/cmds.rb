module CMD
  def start(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.system %{
        ./gradlew installRelease && adb shell am start -n com.dayzerostudio.polymnia/.MainActivity
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
