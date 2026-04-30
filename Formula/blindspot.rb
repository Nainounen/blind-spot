class Blindspot < Formula
  desc "AI answers for selected text — invisible to screen recorders"
  homepage "https://github.com/Nainounen/blind-spot"
  license "MIT"

  # Update url + sha256 after tagging a release:
  #   git tag v1.0.0 && git push origin v1.0.0
  #   curl -L https://github.com/Nainounen/blind-spot/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
  url "https://github.com/Nainounen/blind-spot/archive/refs/heads/main.tar.gz"
  version "1.0.0"
  sha256 :no_check

  head "https://github.com/Nainounen/blind-spot.git", branch: "main"

  depends_on :macos => :sonoma
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release"

    app = prefix/"BlindSpot.app/Contents"
    (app/"MacOS").mkpath

    cp ".build/release/BlindSpot", app/"MacOS/BlindSpot"

    (app/"Info.plist").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleExecutable</key>      <string>BlindSpot</string>
        <key>CFBundleIdentifier</key>      <string>com.blindspot.app</string>
        <key>CFBundleName</key>            <string>BlindSpot</string>
        <key>CFBundleVersion</key>         <string>#{version}</string>
        <key>CFBundleShortVersionString</key><string>#{version}</string>
        <key>CFBundlePackageType</key>     <string>APPL</string>
        <key>LSMinimumSystemVersion</key>  <string>14.0</string>
        <key>LSUIElement</key>             <true/>
        <key>NSAccessibilityUsageDescription</key>
        <string>BlindSpot reads your selected text to answer AI questions.</string>
      </dict></plist>
    XML

    # Symlink binary so `BlindSpot` works from terminal too
    bin.install_symlink app/"MacOS/BlindSpot"
  end

  def caveats
    <<~EOS
      Launch BlindSpot:
        open #{prefix}/BlindSpot.app

      Or from the terminal:
        BlindSpot

      On first launch macOS may show a security warning.
      Go to System Settings → Privacy & Security → Open Anyway.

      To auto-start at login, add BlindSpot.app to Login Items:
        System Settings → General → Login Items → Add…
    EOS
  end

  test do
    assert_predicate bin/"BlindSpot", :exist?
  end
end
