module CMD
  def sync_to_usb(opts)
    opts.banner = "Usage: sync_to_usb"
    opts.info = "Sync music from ProtonDrive to USB"
    lambda { |*args|
      EXE.fish %{
        ./scripts/sync-to-usb.fish
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
