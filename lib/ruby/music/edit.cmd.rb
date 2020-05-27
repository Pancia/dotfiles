require 'music/music_db.rb'

module MusicCMD

  def _edit_impl(item)
    p item if $options[:verbose]
    p $options[:filter] if $options[:verbose]
    if $options[:search] or not item
      items = self._search_impl("--query #{item or "\"\""}").split "\n"
      items.reduce([]) { |to_edit, x|
        to_edit.concat MusicDB.select x, $options[:filter]
      }
    else
      MusicDB.select item.gsub(/\..*$/, ""), $options[:filter]
    end
  end

  def _edit_ask(edit_me)
    field = Readline.readline(">?:".reverse).chomp
    case
    when edit_me.include?(field) || ["tags", "marked"].include?(field)
      RbReadline.prefill_prompt(edit_me[field].to_s)
      new_entry = Readline.readline((field+">?:").reverse).chomp
      edit_me[field] = new_entry
    when "" == field
      return
    else
      puts "INVALID FIELD"
    end
    _edit_ask edit_me
  end

  def edit(opts)
    opts.banner = "Usage: edit [OPTS] ITEM"
    opts.info = "Edit the item interactively"
    opts.separator "    ITEM: String, will be compared in `jq` to FILTER"
    opts.separator ""
    opts.on("-f", "--filter FILTER", "Any string that `jq` will accept -- default: .playlist") { |jqf|
      $options[:filter] = jqf
    }
    opts.on("-s", "--search", "Search for items to edit") {
      $options[:search] = true
    }
    lambda { |item = nil|
      $options[:filter] = ".playlist" if not $options[:filter]
      music = MusicDB.read
      tags = music.values.reduce([]) { |tags, x|
        tags.concat((x["tags"] || "").split(",")).uniq
      }
      puts "TAGS: #{tags}"
      to_edit = _edit_impl(item)
      raise "FAILED TO FIND ANY ITEMS" if to_edit.empty?
      to_edit.each do |edit_me|
        puts
        pp edit_me
        _edit_ask edit_me
      end
      to_edit = to_edit.reduce({}) { |m, s|
        m[s["id"]] = s; m
      }
      MusicDB.save music.merge to_edit
      MusicDB.tag to_edit.values
    }
  end

end
