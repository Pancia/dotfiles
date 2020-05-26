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
  def self.doreg(opts)
    opts.info = "Execute a register."
    lambda { |name|
      if File.exists? reg_file(name)
        execute(File.read(reg_file(name)))
      else
        puts "Register #{name} does not exist yet!"
      end
    }
  end
  def self.list(opts)
    opts.info = "Show all set registers."
    lambda {
      execute("cd #{$home_dir} && bat .config/q/*")
    }
  end
  def self.delreg(opts)
    opts.info = "Delete a register."
    lambda { |name|
      execute("zsh -ic 'trash #{reg_file(name)}'")
    }
  end
end

CLI.parse! CMDS
