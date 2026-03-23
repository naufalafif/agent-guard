class AgentGuard < Formula
  desc "macOS menu bar security scanner for MCP servers and AI agent skills"
  homepage "https://github.com/naufalafif/agent-guard"
  url "https://github.com/naufalafif/agent-guard/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "d4679bb627de218d916a9d401b1e5566ab8a7507a63543e29f302cc592d41f28"
  license "MIT"

  depends_on :macos
  depends_on "uv"

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # Create .app bundle with icon
    app_contents = prefix/"AgentGuard.app/Contents"
    (app_contents/"MacOS").mkpath
    (app_contents/"Resources").mkpath
    (app_contents/"MacOS").install ".build/release/AgentGuard"
    app_contents.install "Info.plist"
    (app_contents/"Resources").install "AppIcon.icns"

    # Ad-hoc sign
    system "codesign", "--force", "--sign", "-", prefix/"AgentGuard.app"
  end

  def post_install
    ohai "Installing mcp-scanner..."
    system "uv", "tool", "install", "cisco-ai-mcp-scanner"

    ohai "Installing skill-scanner..."
    system "uv", "tool", "install", "cisco-ai-skill-scanner"

    # Symlink to /Applications for Spotlight
    app = prefix/"AgentGuard.app"
    target = Pathname.new("/Applications/AgentGuard.app")
    target.unlink if target.symlink? || target.exist?
    target.make_symlink(app)

    # Initialize config and cache
    config_dir = Pathname.new(Dir.home)/".config/mcp-scan"
    cache_dir = Pathname.new(Dir.home)/".cache/mcp-scan"
    config_dir.mkpath
    cache_dir.mkpath
    unless (config_dir/"config").exist?
      (config_dir/"config").write("SCAN_INTERVAL=30  # Scan interval in minutes\n")
    end
    unless (cache_dir/"ignore.json").exist?
      (cache_dir/"ignore.json").write("[]\n")
    end
  end

  def caveats
    <<~EOS
      To start AgentGuard:
        open /Applications/AgentGuard.app

      Or search "AgentGuard" in Spotlight.

      To launch at login:
        Open AgentGuard > Settings > Launch at login
    EOS
  end

  test do
    assert_predicate prefix/"AgentGuard.app/Contents/MacOS/AgentGuard", :exist?
    assert_predicate prefix/"AgentGuard.app/Contents/Resources/AppIcon.icns", :exist?
  end
end
