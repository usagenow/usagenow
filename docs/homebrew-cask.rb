# Homebrew cask for UsageNow.
#
# Fill in the checksum only from the final notarized disk image:
#
#     shasum -a 256 build/release/UsageNow-0.2.0.dmg
#
# Then submit this file to homebrew/homebrew-cask as Casks/u/usagenow.rb.

cask "usagenow" do
  version "0.2.0"
  sha256 "15b7ce8c26770e9d401df494aa842691b7fb242f04a0849cd3802465a734d4bc"

  url "https://github.com/usagenow/usagenow/releases/download/v#{version}/UsageNow-#{version}.dmg",
      verified: "github.com/usagenow/usagenow/"
  name "UsageNow"
  desc "AI coding usage tracker for Codex and Claude Code"
  homepage "https://usagenow.com/"

  depends_on macos: ">= :sequoia"

  app "UsageNow.app"

  zap trash: [
    "~/Library/Group Containers/*.group.com.usagenow.UsageNow",
    "~/Library/Preferences/com.usagenow.UsageNow.plist",
  ]
end
