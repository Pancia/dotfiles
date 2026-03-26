module CMD
  def start(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.fish %{
        set -gx GRADLE_USER_HOME /tmp/gradle-home
        ./gradlew spotlessApply --no-daemon && ./gradlew installDebug --no-daemon
      }
    }
  end

  def build(opts)
    opts.banner = "Usage: install FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.fish %{
        set -gx GRADLE_USER_HOME /tmp/gradle-home
        ./gradlew spotlessApply --no-daemon && ./gradlew assembleDebug --no-daemon
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
