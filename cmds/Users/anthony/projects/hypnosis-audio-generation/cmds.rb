module CMD
  def gen_local(opts)
    opts.banner = "Usage: gen_local [args...]"
    opts.info = "Generate mock audio locally, split chapters, output to Cloud"
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
