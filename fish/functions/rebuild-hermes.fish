function rebuild-hermes -d "Rebuild and restart the Hermes launcher"
    echo "Building Hermes..."
    swift build -c release -C ~/projects/hermes
    and cp ~/projects/hermes/.build/release/Hermes ~/.local/bin/hermes
    and echo "Restarting service..."
    and service restart hermes
    and echo "Hermes rebuilt and restarted."
end
