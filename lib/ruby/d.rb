require "cli.rb"

$home_dir = %x[echo $HOME].strip

system("mkdir -p #{$home_dir}/.config/d")

def execute(cmd)
  puts cmd if $options[:verbose]
  system(cmd)
end

def bookmark_file(name)
  "#{$home_dir}/.config/d/#{name}"
end

class CMDS
  def self.setbookmark(opts)
    opts.info = "Bookmark a directory path"
    lambda { |name, path|
      File.write(bookmark_file(name), path)
    }
  end
  def self.getbookmark(opts)
    opts.info = "Prints the bookmarked directory path."
    lambda { |name|
      if File.exists? bookmark_file(name)
        puts File.read(bookmark_file(name))
      else
        STDERR.puts "Register #{name} does not exist yet!"
      end
    }
  end
  def self.show(opts)
    opts.info = "Show (? all) bookmarks(s)."
    lambda { |*args|
      bookmarks = Dir["#{$home_dir}/.config/d/#{args[0] or "*"}"].map{|r|File.basename(r)}.sort
      max_len = bookmarks.max_by(&:length).length
      bookmarks.each { |bookmark|
        puts("%-#{max_len}s -> %s" % [bookmark, File.read("#{bookmark_file(bookmark)}")])
      }
    }
  end
  def self.delbookmark(opts)
    opts.info = "Delete a bookmark."
    lambda { |name|
      execute("zsh -ic 'trash #{bookmark_file(name)}'")
    }
  end
end

# NOTE: [[~/dotfiles/wiki/zsh_completion.wiki]]
CLI.parse!(CMDS) { |opts|
  opts.on("-z", "--zsh-completions", "print zsh completion") do
    bookmarks = Dir["#{$home_dir}/.config/d/*"].map{|r|File.basename r}.join " "
    puts ["_arguments","1: :(#{bookmarks})","*:::arg:{_normal}"].join "&"
    $options[:helped] = true
  end
}
