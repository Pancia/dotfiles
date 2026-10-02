module CMD
  def test(opts)
    opts.banner = "Usage: test [file.test.js]"
    opts.info = "Run the extension's regression tests (all suites, or just the named one)"
    lambda { |*args|
      target = args.empty? ? "test/run.js" : "test/#{args.first.sub(%r{\Atest/}, "")}"
      EXE.bash %{
        cd /Users/anthony/projects/sekhmet && node #{target}
      }
    }
  end

  def check(opts)
    opts.banner = "Usage: check"
    opts.info = "Parse every .js and confirm the manifest's files all exist"
    lambda { |*args|
      EXE.bash %{
        cd /Users/anthony/projects/sekhmet && node test/check.js
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
