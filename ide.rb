require "gtk4"
require "fileutils"
require "open3"
require "shellwords"

class ZylixlioIDE < Gtk::Box
  def initialize
    super(:vertical, 6)

    set_hexpand(true)
    set_vexpand(true)

    @current_file = nil
    @project_dir = File.expand_path("IDEProjects", __dir__)

    FileUtils.mkdir_p(@project_dir)

    build_toolbar
    build_workspace
    refresh_files
  end

  def build_toolbar
    toolbar = Gtk::Box.new(:horizontal, 8)
    toolbar.set_margin_start(10)
    toolbar.set_margin_top(10)
    toolbar.set_margin_bottom(10)

    new_button = Gtk::Button.new(label: "New")
    open_button = Gtk::Button.new(label: "Open")
    save_button = Gtk::Button.new(label: "Save")
    run_button = Gtk::Button.new(label: "▶ Run")

    @filename = Gtk::Entry.new
    @filename.set_placeholder_text("Filename: main.py")
    @filename.set_text("main.py")
    @filename.set_hexpand(true)

    new_button.signal_connect("clicked") { new_file }
    open_button.signal_connect("clicked") { open_named_file }
    save_button.signal_connect("clicked") { save_file }
    run_button.signal_connect("clicked") { run_file }

    toolbar.append(new_button)
    toolbar.append(open_button)
    toolbar.append(save_button)
    toolbar.append(run_button)
    toolbar.append(@filename)

    append(toolbar)
  end

  def build_workspace
    paned = Gtk::Paned.new(:horizontal)
    paned.set_vexpand(true)
    paned.set_position(230)

    sidebar = Gtk::Box.new(:vertical, 5)

    label = Gtk::Label.new("PROJECT FILES")
    sidebar.append(label)

    @files = Gtk::ListBox.new
    @files.set_selection_mode(:single)

    @files.signal_connect("row-activated") do |_list, row|
      open_file(row.name)
    end

    file_scroll = Gtk::ScrolledWindow.new
    file_scroll.set_vexpand(true)
    file_scroll.set_child(@files)
    sidebar.append(file_scroll)

    paned.set_start_child(sidebar)

    right = Gtk::Paned.new(:vertical)
    right.set_position(450)

    @editor = Gtk::TextView.new
    @editor.set_monospace(true)
    @editor.set_wrap_mode(:none)

    editor_scroll = Gtk::ScrolledWindow.new
    editor_scroll.set_hexpand(true)
    editor_scroll.set_vexpand(true)
    editor_scroll.set_child(@editor)

    right.set_start_child(editor_scroll)

    @output = Gtk::TextView.new
    @output.set_monospace(true)
    @output.set_editable(false)

    output_scroll = Gtk::ScrolledWindow.new
    output_scroll.set_vexpand(true)
    output_scroll.set_child(@output)

    right.set_end_child(output_scroll)
    paned.set_end_child(right)

    append(paned)
  end

  def safe_path(name)
    name = File.basename(name.to_s.strip)
    return nil if name.empty? || name == "."

    File.join(@project_dir, name)
  end

  def new_file
    path = safe_path(@filename.text)
    return unless path

    if File.exist?(path)
      puts "File already exists: #{path}"
      return
    end

    File.write(path, "")
    @current_file = path
    @editor.buffer.set_text("")
    refresh_files
  end

  def open_named_file
    path = safe_path(@filename.text)
    open_file(path) if path
  end

  def open_file(path)
    path = safe_path(path)
    return unless path && File.file?(path)

    @current_file = path
    @filename.set_text(File.basename(path))
    @editor.buffer.set_text(File.read(path))
  rescue StandardError => e
    set_output("Open error: #{e.message}")
  end

  def save_file
    path = @current_file || safe_path(@filename.text)
    return unless path

    buffer = @editor.buffer
    text = buffer.get_text(
      buffer.start_iter,
      buffer.end_iter,
      false
    )

    File.write(path, text)
    @current_file = path
    refresh_files
    set_output("Saved: #{path}")
  rescue StandardError => e
    set_output("Save error: #{e.message}")
  end

  def refresh_files
    while (child = @files.first_child)
      @files.remove(child)
    end

    Dir.children(@project_dir).sort.each do |name|
      next unless File.file?(File.join(@project_dir, name))

      row = Gtk::ListBoxRow.new
      row.set_name(name)
      row.set_child(Gtk::Label.new(name))
      @files.append(row)
    end
  end

  def set_output(text)
    @output.buffer.set_text(text.to_s)
  end

  def run_file
    save_file
    return unless @current_file

    ext = File.extname(@current_file)

    command = case ext
    when ".py" then ["python3", @current_file]
    when ".rb" then ["ruby", @current_file]
    when ".js" then ["node", @current_file]
    when ".lua" then ["lua", @current_file]
    when ".sh" then ["bash", @current_file]
    when ".c"
      binary = File.join(@project_dir, "zylixlio_run")
      compile = ["gcc", @current_file, "-o", binary]
      stdout, stderr, status = Open3.capture3(*compile)
      unless status.success?
        set_output(stdout + stderr)
        return
      end
      [binary]
    when ".cpp"
      binary = File.join(@project_dir, "zylixlio_run")
      compile = ["g++", @current_file, "-o", binary]
      stdout, stderr, status = Open3.capture3(*compile)
      unless status.success?
        set_output(stdout + stderr)
        return
      end
      [binary]
    else
      set_output("No runner configured for #{ext}")
      return
    end

    set_output("Running #{File.basename(@current_file)}...")

    Thread.new do
      begin
        stdout, stderr, status = Open3.capture3(*command)
        result = stdout + stderr + "\nExit code: #{status.exitstatus}"

        GLib::Idle.add do
          set_output(result)
          false
        end
      rescue StandardError => e
        GLib::Idle.add do
          set_output("Run error: #{e.message}")
          false
        end
      end
    end
  end
end
