require 'gtk4'
require 'fileutils'

class ZylixlioTextEditor < Gtk::Box
  def initialize
    super(:vertical, 5)

    set_hexpand(true)
    set_vexpand(true)

    @current_file = nil

    # Create Documents directory
    FileUtils.mkdir_p("Documents")

    # Toolbar
    toolbar = Gtk::Box.new(:horizontal, 5)
    append(toolbar)

    # New button
    new_button = Gtk::Button.new(label: "New")
    toolbar.append(new_button)

    # Save button
    save_button = Gtk::Button.new(label: "Save")
    toolbar.append(save_button)

    # Current filename label
    @file_label = Gtk::Label.new("No file selected")
    toolbar.append(@file_label)

    # Text editor
    @text_view = Gtk::TextView.new
    @text_view.set_monospace(true)
    @text_view.set_wrap_mode(:none)

    scroll = Gtk::ScrolledWindow.new
    scroll.set_hexpand(true)
    scroll.set_vexpand(true)
    scroll.set_child(@text_view)

    append(scroll)

    # NEW FILE
    new_button.signal_connect("clicked") do
      number = 1

      while File.exist?("Documents/document#{number}.txt")
        number += 1
      end

      @current_file = "Documents/document#{number}.txt"

      File.write(@current_file, "")

      @text_view.buffer.set_text("")
      @file_label.set_text("document#{number}.txt")

      puts "Created: #{@current_file}"
    end

    # SAVE FILE
    save_button.signal_connect("clicked") do
      if @current_file
        buffer = @text_view.buffer

        text = buffer.get_text(
          buffer.start_iter,
          buffer.end_iter,
          false
        )

        File.write(@current_file, text)

        puts "Saved: #{@current_file}"
      else
        puts "Create a file first!"
      end
    end
  end
end