require "gtk4"
require_relative "browser"
require_relative "texteditor"
require_relative "ide"

app = Gtk::Application.new(
  "com.zylixlio.main",
  :flags_none
)

app.signal_connect("activate") do
  window = Gtk::ApplicationWindow.new(app)
  window.set_title("Zylixlio")

  # Main container
  root = Gtk::Box.new(:vertical, 0)
  root.set_hexpand(true)
  root.set_vexpand(true)

  # Header
  header = Gtk::Box.new(:horizontal, 12)
  header.set_margin_top(10)
  header.set_margin_bottom(10)
  header.set_margin_start(15)
  header.set_margin_end(15)

  title = Gtk::Label.new
  title.set_markup(
    "<span size='32000' weight='bold'>Zylixlio</span>"
  )
  title.set_halign(:start)
  title.set_hexpand(true)

  header.append(title)

  root.append(header)

  # App switching buttons — NOT browser tabs
  navigation = Gtk::Box.new(:horizontal, 8)
  navigation.set_margin_start(15)
  navigation.set_margin_end(15)
  navigation.set_margin_bottom(10)

  root.append(navigation)

  # Each app gets its own full-size box
  stack = Gtk::Stack.new
  stack.set_hexpand(true)
  stack.set_vexpand(true)

  # Prevent transitions from interfering with WebKit
  stack.set_transition_type(:none)

  browser = ZylixlioBrowser.new(window)
  editor = ZylixlioTextEditor.new
  ide = ZylixlioIDE.new

  stack.add_named(browser, "browser")
  stack.add_named(editor, "editor")
  stack.add_named(ide, "ide")

  apps = [
    ["🌐 Browser", "browser"],
    ["📝 Text Editor", "editor"],
    ["💻 IDE", "ide"]
  ]

  apps.each do |name, page|
    button = Gtk::Button.new(label: name)
    button.set_hexpand(true)

    button.signal_connect("clicked") do
      stack.set_visible_child_name(page)
    end

    navigation.append(button)
  end

  stack.set_visible_child_name("browser")

  root.append(stack)

  window.set_child(root)
  window.fullscreen
  window.present
end

app.run
