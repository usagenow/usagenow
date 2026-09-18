# Homebrew cask for UsageNow, kept ready for homebrew/homebrew-cask.
#
# Not submitted yet: Homebrew accepts a new cask only when the upstream
# repository is at least 30 days old and has 30 forks, 30 watchers, or 75 stars.
# Once usagenow/usagenow clears that, submit this file as Casks/u/usagenow.rb.
#
# On every release, update the version and the checksum of the notarized image:
#
#     shasum -a 256 build/release/UsageNow-<version>.dmg
#
# Verified on 2026-09-16 against the 0.3.0 release (checksum since updated for 0.4.0): brew style, brew audit
# --cask --online --strict, and an install/uninstall cycle all passed.

cask "usagenow" do
  version "0.5.0"
  sha256 "f926c692678e825bcaad6cf827b4fe8cb8ac21cedc5a397660813ffcb69932f1"

  url "https://github.com/usagenow/usagenow/releases/download/v#{version}/UsageNow-#{version}.dmg"
  name "UsageNow"
  desc "AI coding usage tracker for Codex, Claude Code, Gemini CLI, and Antigravity"
  homepage "https://usagenow.com/"

  depends_on macos: :sequoia

  app "UsageNow.app"

  zap trash: [
    "~/Library/Group Containers/*.group.com.usagenow.UsageNow",
    "~/Library/Preferences/com.usagenow.UsageNow.plist",
  ]
end
