class AgentGuard < Formula
  desc "macOS menu bar security scanner for MCP servers and AI agent skills"
  homepage "https://github.com/naufalafif/agent-guard"
  url "https://github.com/naufalafif/agent-guard/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER"
  license "MIT"

  depends_on :macos
  depends_on "uv"

  def install
    # Build the Swift binary
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # Create .app bundle
    app_bundle = prefix/"AgentGuard.app/Contents"
    (app_bundle/"MacOS").mkpath
    (app_bundle/"MacOS").install ".build/release/AgentGuard"
    (app_bundle).install "Info.plist"

    # Install mcp-scanner and skill-scanner via uv
    system "uv", "tool", "install", "cisco-ai-mcp-scanner"
    system "uv", "tool", "install", "cisco-ai-skill-scanner"
  end

  def post_install
    # Initialize config and cache
    (var/"cache/mcp-scan").mkpath
    config_dir = etc/"mcp-scan"
    config_dir.mkpath
    unless (config_dir/"config").exist?
      (config_dir/"config").write "SCAN_INTERVAL=30\n"
    end
    unless (var/"cache/mcp-scan/ignore.json").exist?
      (var/"cache/mcp-scan/ignore.json").write "[]\n"
    end
  end

  def caveats
    <<~EOS
      AgentGuard has been installed to:
        #{prefix}/AgentGuard.app

      To start AgentGuard:
        open #{prefix}/AgentGuard.app

      To launch at login:
        Add AgentGuard to System Settings > General > Login Items

      Scanners installed:
        mcp-scanner (MCP server security)
        skill-scanner (AI agent skill security)
    EOS
  end

  test do
    system "#{prefix}/AgentGuard.app/Contents/MacOS/AgentGuard", "--help" rescue nil
    assert_predicate prefix/"AgentGuard.app/Contents/MacOS/AgentGuard", :exist?
  end
end
