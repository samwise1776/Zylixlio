require_relative "password_manager"

require "gtk4"
require "webkit-gtk"
require "uri"
require "cgi"

class ZylixlioBrowser < Gtk::Box
  HOME = "https://www.google.com"

  CSS = <<~CSS
    .z-browser {
      background: #101520;
      color: #e5eeff;
    }

    .z-toolbar {
      background: #151d2b;
      padding: 9px;
      border-bottom: 1px solid #2b3952;
    }

    .z-address {
      background: #222e43;
      color: #f3f7ff;
      border: 1px solid #344661;
      border-radius: 12px;
      padding: 9px 14px;
      min-height: 22px;
    }

    .z-address:focus {
      border-color: #6d9eff;
    }

    .z-nav {
      background: transparent;
      color: #c8d8f3;
      border: none;
      border-radius: 9px;
      min-width: 35px;
      min-height: 35px;
      font-size: 17px;
    }

    .z-nav:hover {
      background: #30415b;
    }

    .z-nav:disabled {
      opacity: 0.3;
    }

    .z-tabs {
      background: #101520;
    }

    .z-tabs header {
      background: #141c29;
      border: none;
    }

    .z-tabs tab {
      background: #1a2535;
      color: #b9cce9;
      padding: 8px 14px;
      border-radius: 8px 8px 0 0;
      margin: 3px 2px 0 2px;
    }

    .z-tabs tab:checked {
      background: #263750;
      color: white;
    }

    .z-tab-close {
      background: transparent;
      border: none;
      padding: 1px 5px;
      min-height: 20px;
      min-width: 20px;
    }

    .z-tab-close:hover {
      background: #b84d62;
      color: white;
    }

    .z-status {
      background: #151d2b;
      color: #91a8c9;
      font-size: 11px;
      padding: 5px 12px;
    }
  CSS

  def self.install_css
    return if @css_installed

    provider = Gtk::CssProvider.new

    if provider.respond_to?(:load_from_string)
      provider.load_from_string(CSS)
    else
      provider.load(data: CSS)
    end

    Gtk::StyleContext.add_provider_for_display(
      Gdk::Display.default,
      provider,
      600
    )

    @css_installed = true
  end

  def initialize(parent_window = nil)
    super(:vertical, 0)
    @parent_window = parent_window

    ZylixlioBrowser.install_css

    add_css_class("z-browser")
    set_hexpand(true)
    set_vexpand(true)

    @views = {}

    build_toolbar
    build_tabs
    build_status

    new_tab
  end

  def nav_button(label, tooltip, &action)
    button = Gtk::Button.new(label: label)
    button.add_css_class("z-nav")
    button.set_tooltip_text(tooltip)

    button.signal_connect("clicked") do
      action.call
    end

    button
  end

  def build_toolbar
    toolbar = Gtk::Box.new(:horizontal, 6)
    toolbar.add_css_class("z-toolbar")

    @back_button = nav_button("←", "Go back") do
      current_view&.go_back
    end

    @forward_button = nav_button("→", "Go forward") do
      current_view&.go_forward
    end

    @reload_button = nav_button("⟳", "Reload") do
      current_view&.reload
    end

    @home_button = nav_button("⌂", "Home") do
      current_view&.load_uri(HOME)
    end

    @address = Gtk::Entry.new
    @address.add_css_class("z-address")
    @address.set_placeholder_text("Search or enter a URL")
    @address.set_hexpand(true)

    @address.signal_connect("activate") do
      navigate(@address.text)
    end

    @new_button = nav_button("+", "New tab") do
      new_tab
    end

    toolbar.append(@back_button)
    toolbar.append(@forward_button)
    toolbar.append(@reload_button)
    toolbar.append(@home_button)
    toolbar.append(@address)
    toolbar.append(@new_button)

    @password_button = nav_button("🔑", "Password Manager") do
      begin
        ZylixlioPasswordManager.new(@parent_window).present
      rescue StandardError => e
        warn "Password Manager Error: #{e.full_message}"
      end
    end
    toolbar.append(@password_button)


    append(toolbar)
  end

  def build_tabs
    @notebook = Gtk::Notebook.new
    @notebook.add_css_class("z-tabs")
    @notebook.set_scrollable(true)
    @notebook.set_show_border(false)
    @notebook.set_hexpand(true)
    @notebook.set_vexpand(true)

    @notebook.signal_connect("switch-page") do
      update_toolbar
    end

    append(@notebook)
  end

  def build_status
    @status = Gtk::Label.new("Zylixlio Browser • Ready")
    @status.add_css_class("z-status")
    @status.set_halign(:start)

    append(@status)
  end

  def current_view
    index = @notebook.current_page
    return nil if index.nil? || index < 0

    @notebook.get_nth_page(index)
  end

  def navigate(input)
    input = input.to_s.strip
    return if input.empty?

    url =
      if input.match?(/\Ahttps?:\/\//i)
        input
      elsif input.match?(/\A(?:localhost|127\.0\.0\.1)(?::\d+)?(?:\/.*)?\z/i)
        "http://#{input}"
      elsif input.match?(/\A(?:about:|file:\/\/)/i)
        input
      elsif input.match?(/\A[^\s]+\.[a-z]{2,}(?::\d+)?(?:[\/?#].*)?\z/i)
        "https://#{input}"
      else
        "https://www.google.com/search?q=#{URI.encode_www_form_component(input)}"
      end

    puts "[Zylixlio] Navigating: #{url}"
    if current_view
      current_view.load_uri(url)
    else
      warn "[Zylixlio] No active browser tab"
    end
  end

  def new_tab(url = nil)
    view = WebKitGtk::WebView.new
    view.set_hexpand(true)
    view.set_vexpand(true)

    # Tab label
    tab_box = Gtk::Box.new(:horizontal, 6)

    title = Gtk::Label.new("New Tab")
    title.set_max_width_chars(22)
    title.set_ellipsize(Pango::EllipsizeMode::END)

    close = Gtk::Button.new(label: "×")
    close.add_css_class("z-tab-close")
    close.set_tooltip_text("Close tab")

    tab_box.append(title)
    tab_box.append(close)

    @views[view] = view

    @notebook.append_page(view, tab_box)
    @notebook.set_current_page(@notebook.page_num(view))

    close.signal_connect("clicked") do
      close_tab(view)
    end

    view.signal_connect("notify::title") do
      value = view.title.to_s.strip
      title.set_text(value.empty? ? "New Tab" : value)
    end

    view.signal_connect("notify::uri") do
      update_toolbar if current_view == view
    end

    view.signal_connect("notify::estimated-load-progress") do
      if current_view == view
        progress = (view.estimated_load_progress * 100).to_i
        @status.set_text("Loading... #{progress}%")
      end
    end

    view.signal_connect("load-changed") do |_, event|
      if current_view == view
        update_toolbar

        if event.to_s.downcase.include?("finished")
          @status.set_text("Zylixlio Browser • Ready")
        end
      end
    end

    # Open target=_blank links in a new tab
    view.signal_connect("create") do |_webview, _navigation_action|
      new_tab
    end

    if url
      view.load_uri(url)
    else
      load_start_page(view)
    end

    update_toolbar
    view
  end

  def close_tab(view)
    page_number = @notebook.page_num(view)

    return if page_number.nil? || page_number < 0

    @notebook.remove_page(page_number)
    @views.delete(view)

    new_tab if @views.empty?

    update_toolbar
  end

  def update_toolbar
    view = current_view
    return unless view

    @address.set_text(view.uri.to_s)

    @back_button.set_sensitive(view.can_go_back?)
    @forward_button.set_sensitive(view.can_go_forward?)
  end

  def load_start_page(view)
    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>New Tab</title>
        <style>
          * { box-sizing: border-box; }

          body {
            margin: 0;
            min-height: 100vh;
            background:
              radial-gradient(circle at 50% 20%, #263d65, transparent 55%),
              #101827;
            color: #eaf2ff;
            font-family: system-ui, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          main {
            width: min(620px, 90vw);
            text-align: center;
          }

          h1 {
            font-size: 64px;
            letter-spacing: -3px;
            margin: 0 0 8px;
            background: linear-gradient(90deg, #80aaff, #c4a4ff);
            color: transparent;
            background-clip: text;
          }

          p {
            color: #91a9ca;
            margin-bottom: 36px;
          }

          form {
            display: flex;
            background: #24334b;
            border: 1px solid #3b5375;
            border-radius: 16px;
            padding: 7px;
          }

          input {
            flex: 1;
            background: transparent;
            border: none;
            outline: none;
            color: white;
            padding: 14px;
            font-size: 16px;
            min-width: 0;
          }

          button {
            background: #6899ff;
            color: #101827;
            border: none;
            padding: 0 22px;
            border-radius: 11px;
            cursor: pointer;
            font-weight: bold;
          }

          .links {
            display: flex;
            justify-content: center;
            gap: 16px;
            margin-top: 34px;
            flex-wrap: wrap;
          }

          .links a {
            color: #c4d6f5;
            text-decoration: none;
            background: #22324c;
            padding: 18px;
            border-radius: 13px;
            min-width: 110px;
            transition: background 0.2s;
          }

          .links a:hover {
            background: #344f77;
          }

          footer {
            margin-top: 65px;
            color: #7187a9;
            font-size: 12px;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Zylixlio</h1>
          <p>One workspace. Infinite possibilities.</p>

          <form action="https://www.google.com/search" method="GET">
            <input
              name="q"
              placeholder="Search anything..."
              autofocus
            >
            <button type="submit">Search</button>
          </form>

          <div class="links">
            <a href="https://github.com">⌘ GitHub</a>
            <a href="https://youtube.com">▶ YouTube</a>
            <a href="https://www.wikipedia.org">◈ Wikipedia</a>
            <a href="https://docs.gtk.org">▣ GTK Docs</a>
          </div>

          <footer>ZYLIXLIO BROWSER</footer>
        </main>
      </body>
      </html>
    HTML

    view.load_html(html, "https://zylixlio.local/")
  end
end
