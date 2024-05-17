require "cli.rb"

$home_dir = %x[echo $HOME].strip

system("mkdir -p #{$home_dir}/.config/q")

def execute(cmd)
  puts cmd if $options[:verbose]
  system(cmd)
end

def reg_file(name)
  "#{$home_dir}/.config/q/#{name}"
end

class CMDS
  def self.setreg(opts)
    opts.info = "Set a register."
    lambda { |name, *args|
      File.write(reg_file(name), args.join(" "))
    }
  end
  def self.getreg(opts)
    opts.info = "Prints the register file path."
    lambda { |name, *args|
      if File.exist? reg_file(name)
        puts reg_file(name)
      else
        STDERR.puts "Register #{name} does not exist yet!"
      end
    }
  end
  def self.show(opts)
    opts.info = "Show (all) register(s)."
    lambda { |*args|
      registers = Dir["#{$home_dir}/.config/q/#{args[0] or "*"}"].map{|r|File.basename(r)}.sort
      max_len = registers.max_by(&:length).length
      registers.each { |reg|
        puts("%-#{max_len}s -> %s" % [reg, File.read("#{reg_file(reg)}")])
      }
    }
  end
  def self.delreg(opts)
    opts.info = "Delete a register."
    lambda { |name|
      execute("zsh -ic 'trash #{reg_file(name)}'")
    }
  end
  def self.editreg(opts)
    opts.info = "Edit a register using $EDITOR."
    lambda { |name|
      execute("$EDITOR #{reg_file(name)}")
    }
  end
end

# NOTE: [[~/dotfiles/wiki/zsh_completion.wiki]]
CLI.parse!(CMDS) { |opts|
  opts.on("-z", "--zsh-completions", "print zsh completion") do
    registers = Dir["#{$home_dir}/.config/q/*"].map{|r|File.basename r}.join " "
    puts ["_arguments","1: :(#{registers})","*:::arg:{_normal}"].join "&"
    $options[:helped] = true
  end
}
