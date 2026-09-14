# Homebrew cask for UsageNow.
#
# Fill in the checksum only from the final notarized disk image:
#
#     shasum -a 256 build/release/UsageNow-0.3.0.dmg
#
# Then submit this file to homebrew/homebrew-cask as Casks/u/usagenow.rb.

cask "usagenow" do
  version "0.3.0"
  sha256 "d036b78583a6e6aa52b5a1e726b5afcf720cd8537511c7375b0e62fc23e63bc3"

  url "https://github.com/usagenow/usagenow/releases/download/v#{version}/UsageNow-#{version}.dmg",
      verified: "github.com/usagenow/usagenow/"
  name "UsageNow"
  desc "AI coding usage tracker for Codex, Claude Code, Gemini CLI, and Antigravity"
  homepage "https://usagenow.com/"

  depends_on macos: ">= :sequoia"

  app "UsageNow.app"

  zap trash: [
    "~/Library/Group Containers/*.group.com.usagenow.UsageNow",
    "~/Library/Preferences/com.usagenow.UsageNow.plist",
  ]
end
