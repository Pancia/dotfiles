module CMD
  def example(opts)
    opts.banner = "Usage: example"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.bash %{
        echo "FIXME"
      }
    }
  end

  def gen_local(opts)
    opts.banner = "Usage: gen_local FIXME"
    opts.info = "FIXME"
    lambda { |*args|
      EXE.bash %{
          uv run generate_script_audio.py --mock --split-chapters -o ~/Cloud/hypnosis-vision-quest/audios/ --mock-speed 0.7 -v #{args.join " "}
      }
    }

  end
end

trap "SIGINT" do
  exit 130
end
