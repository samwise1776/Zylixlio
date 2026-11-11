require "gtk4"
require "openssl"
require "json"
require "securerandom"
require "fileutils"
require "base64"

class ZylixlioPasswordManager
  DIR = File.join(Dir.home, ".local", "share", "zylixlio")
  FILE = File.join(DIR, "passwords.vault")
  ITERATIONS = 300_000

  def initialize(parent = nil)
    @window = if parent
      Gtk::ApplicationWindow.new(parent.application)
    else
      Gtk::Window.new
    end
    @window.set_title("Zylixlio Password Manager")
    @window.set_default_size(750, 600)
    @window.set_transient_for(parent) if parent

    @root = Gtk::Box.new(:vertical, 12)
    @root.set_margin_top(20)
    @root.set_margin_bottom(20)
    @root.set_margin_start(24)
    @root.set_margin_end(24)
    @window.set_child(@root)

    @accounts = []
    @master = nil

    unlock_screen

    @window.signal_connect("close-request") do
      @master = nil
      @accounts.clear
      false
    end
  end

  def present
    @window.present
  end

  def clear
    while child = @root.first_child
      @root.remove(child)
    end
  end

  def label(text)
    widget = Gtk::Label.new(text)
    widget.set_halign(:start)
    @root.append(widget)
    widget
  end

  def entry(placeholder, secret = false)
    widget = Gtk::Entry.new
    widget.set_placeholder_text(placeholder)
    widget.set_hexpand(true)
    widget.set_visibility(false) if secret
    @root.append(widget)
    widget
  end

  def button(text, &action)
    widget = Gtk::Button.new(label: text)
    widget.signal_connect("clicked") { action.call }
    @root.append(widget)
    widget
  end

  def message(text)
    @message.set_text(text)
  end

  def unlock_screen
    clear

    label("🔐 Zylixlio Password Manager")
    label(File.exist?(FILE) ? "Unlock your vault" : "Create your encrypted vault")

    @password_input = entry("Master password", true)

    unless File.exist?(FILE)
      label("Use at least 12 characters. Keep this password safe.")
      @confirm_input = entry("Confirm master password", true)
    end

    @message = label("")

    button(File.exist?(FILE) ? "Unlock" : "Create Vault") do
      password = @password_input.text.to_s

      if File.exist?(FILE)
        begin
          @accounts = decrypt_vault(password)
          @master = password
          dashboard
        rescue OpenSSL::Cipher::CipherError, JSON::ParserError, ArgumentError
          message("Incorrect master password or damaged vault.")
        end
      else
        if password.length < 12
          message("Use at least 12 characters.")
        elsif password != @confirm_input.text
          message("Passwords do not match.")
        else
          begin
            @master = password
            @accounts = []
            save_vault
            dashboard
          rescue StandardError => e
            @master = nil
            message("Could not create vault: #{e.message}")
          end
        end
      end
    end
  end

  def derive_key(password, salt)
    OpenSSL::PKCS5.pbkdf2_hmac(
      password, salt, ITERATIONS, 32, "sha256"
    )
  end

  def encrypt_vault
    salt = SecureRandom.random_bytes(16)
    iv = SecureRandom.random_bytes(12)

    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    cipher.key = derive_key(@master, salt)
    cipher.iv = iv
    cipher.auth_data = "zylixlio-vault-v1"

    plaintext = JSON.generate(@accounts)
    encrypted = cipher.update(plaintext) + cipher.final

    JSON.generate({
      "version" => 1,
      "salt" => Base64.strict_encode64(salt),
      "iv" => Base64.strict_encode64(iv),
      "tag" => Base64.strict_encode64(cipher.auth_tag),
      "data" => Base64.strict_encode64(encrypted)
    })
  end

  def decrypt_vault(password)
    record = JSON.parse(File.read(FILE))
    raise ArgumentError, "Unknown vault version" unless record["version"] == 1

    salt = Base64.strict_decode64(record.fetch("salt"))
    iv = Base64.strict_decode64(record.fetch("iv"))
    tag = Base64.strict_decode64(record.fetch("tag"))
    encrypted = Base64.strict_decode64(record.fetch("data"))

    raise ArgumentError, "Invalid salt" unless salt.bytesize == 16
    raise ArgumentError, "Invalid IV" unless iv.bytesize == 12
    raise ArgumentError, "Invalid tag" unless tag.bytesize == 16

    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.decrypt
    cipher.key = derive_key(password, salt)
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = "zylixlio-vault-v1"

    plaintext = cipher.update(encrypted) + cipher.final
    accounts = JSON.parse(plaintext)

    raise ArgumentError, "Invalid vault data" unless accounts.is_a?(Array)
    accounts
  end

  def save_vault
    FileUtils.mkdir_p(DIR, mode: 0700)
    File.chmod(0700, DIR)

    temp = "#{FILE}.#{SecureRandom.hex(8)}.tmp"

    begin
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
        file.write(encrypt_vault)
        file.flush
        file.fsync
      end

      File.rename(temp, FILE)
      File.chmod(0600, FILE)
    ensure
      File.delete(temp) if File.exist?(temp)
    end
  end

  def dashboard
    clear

    label("🔐 Saved Accounts — #{@accounts.length}")

    search = entry("Search websites or usernames...")

    @list = Gtk::ListBox.new
    @list.set_selection_mode(:none)

    scroll = Gtk::ScrolledWindow.new
    scroll.set_hexpand(true)
    scroll.set_vexpand(true)
    scroll.set_child(@list)
    @root.append(scroll)

    search.signal_connect("changed") do
      refresh_list(search.text)
    end

    refresh_list

    button("+ Add Account") { add_screen }
    button("Lock Vault") do
      @master = nil
      @accounts.clear
      unlock_screen
    end
  end

  def refresh_list(query = "")
    while child = @list.first_child
      @list.remove(child)
    end

    @accounts.each_with_index do |account, index|
      searchable = "#{account['site']} #{account['username']}".downcase
      next unless searchable.include?(query.to_s.downcase)

      row = Gtk::Box.new(:vertical, 5)
      row.set_margin_top(10)
      row.set_margin_bottom(10)
      row.set_margin_start(10)
      row.set_margin_end(10)

      site = Gtk::Label.new(account["site"].to_s)
      site.set_halign(:start)
      row.append(site)

      username = Gtk::Label.new("Username: #{account['username']}")
      username.set_halign(:start)
      row.append(username)

      password = Gtk::Entry.new
      password.set_text(account["password"].to_s)
      password.set_visibility(false)
      password.set_editable(false)
      row.append(password)

      actions = Gtk::Box.new(:horizontal, 8)

      reveal = Gtk::Button.new(label: "Show")
      reveal.signal_connect("clicked") do
        visible = !password.visibility?
        password.set_visibility(visible)
        reveal.set_label(visible ? "Hide" : "Show")
      end
      actions.append(reveal)

      delete = Gtk::Button.new(label: "Delete")
      delete.signal_connect("clicked") do
        @accounts.delete_at(index)
        begin
          save_vault
          dashboard
        rescue StandardError => e
          @accounts.insert(index, account)
          warn "Vault save failed: #{e.message}"
          dashboard
        end
      end
      actions.append(delete)

      row.append(actions)
      @list.append(row)
    end
  end

  def add_screen
    clear

    label("➕ Add Website Account")

    site = entry("Website (example.com)")
    username = entry("Username or email")
    password = entry("Password", true)

    show = Gtk::CheckButton.new(label: "Show password")
    show.signal_connect("toggled") do
      password.set_visibility(show.active?)
    end
    @root.append(show)

    @message = label("")

    button("Save Account") do
      if site.text.strip.empty? || username.text.strip.empty? ||
         password.text.empty?
        message("Fill in all fields.")
      else
        @accounts << {
          "site" => site.text.strip,
          "username" => username.text.strip,
          "password" => password.text
        }

        begin
          save_vault
          dashboard
        rescue StandardError => e
          @accounts.pop
          message("Save failed: #{e.message}")
        end
      end
    end

    button("Cancel") { dashboard }
  end
end
