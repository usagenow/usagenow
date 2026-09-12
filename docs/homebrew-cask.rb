# Homebrew cask for UsageNow.
#
# Fill in the checksum only from the final notarized disk image:
#
#     shasum -a 256 build/release/UsageNow-0.2.0.dmg
#
# Then submit this file to homebrew/homebrew-cask as Casks/u/usagenow.rb.

cask "usagenow" do
  version "0.2.0"
  sha256 "FILL_IN_FROM_THE_FINAL_DMG"

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
