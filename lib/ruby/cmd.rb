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

class CMD
  def self.cli!(cmds)
    @program_name = File.basename $PROGRAM_NAME
    cmd_to_opts = (cmds.methods - Object.methods)
      .map {|m| parse_method cmds, m}
      .keep_if {|_,i| i}
      .sort.to_h
    @global_opts = OptionParser.new do |opts|
      opts.banner = "Usage: music [OPTS] COMMAND [ARGS]"
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
        .map {|m,i| "\t"+m.to_s+"\t:\t"+i[:opts].info }
        .join "\n"
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
      end
    end
  end
end
