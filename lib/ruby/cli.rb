require "optparse"

class OptionParser
  def info
    @info
  end
  def info=(str)
    @info = str
    top.append(">>> "+str, nil, nil)
    top.append("", nil, nil)
  end
end

def parse_method(cmds, m)
  action = nil
  o = OptionParser.new { |opts| action = cmds.send(m, opts) }
  [m.to_s, {action: action, opts: o}]
end

$options = {}

class CLI
  def self.parse!(cmds)
    @program_name = File.basename $PROGRAM_NAME
    cmd_to_opts = (cmds.methods - Object.methods)
      .filter {|m| not m.to_s.start_with? "_" and m}
      .map {|m| parse_method cmds, m}
      .filter {|_,i| i}
      .sort.to_h
    @global_opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{@program_name} [OPTS] COMMAND [ARGS]"
      opts.on("-h", "--help", "Print this help document") do
        puts opts if not $options[:helped]
        $options[:helped] = true
      end
      $options[:verbose] = false
      opts.on("-v", "--verbose", "Print more, for debugging") do
        $options[:verbose] = true
      end
      $options[:dry_run] = false
      opts.on("-n", "--dry-run", "Dry Run / Simulation, prints commands instead of executing.") do
        $options[:dry_run] = true
      end
      opts.separator ""
      opts.separator "COMMANDs:"
      opts.separator cmd_to_opts
        .map {|m,i| "\t#{m.to_s}\t:\t#{i[:opts].info}" }
        .join "\n"
      opts.separator ""
      opts.on("--fish-completions", "Print fish shell completions") do
        # Subcommand names with descriptions
        cmd_to_opts.each do |name, info|
          desc = (info[:opts].info || "").gsub("'", "\\\\'")
          puts "complete -c #{@program_name} -f -n '__fish_use_subcommand' -a '#{name}' -d '#{desc}'"
        end
        # Per-subcommand flags
        cmd_to_opts.each do |name, info|
          info[:opts].top.list.each do |sw|
            next unless sw.is_a?(OptionParser::Switch)
            desc = (sw.desc.join(" ") rescue "").gsub("'", "\\\\'")
            short = sw.short&.first&.sub(/^-/, "")
            long = sw.long&.first&.sub(/^--/, "")
            needs_arg = sw.is_a?(OptionParser::Switch::RequiredArgument)
            parts = ["complete -c #{@program_name} -n '__fish_seen_subcommand_from #{name}'"]
            parts << "-s '#{short}'" if short
            parts << "-l '#{long}'" if long
            parts << "-r" if needs_arg
            parts << "-d '#{desc}'" unless desc.empty?
            puts parts.join(" ")
          end
        end
        $options[:helped] = true
      end
      opts.separator ""
      yield opts if block_given?
    end

    @global_opts.order!
    if not $options[:helped]
      if ARGV[0] and cmds.respond_to? ARGV[0]
        command = ARGV.shift
        cmd_to_opts[command][:opts].order! ARGV
        cmd_to_opts[command][:action].call(*ARGV)
      else
        puts @global_opts
        exit 1
      end
    end
  end
end
