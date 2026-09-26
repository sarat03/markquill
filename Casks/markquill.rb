# This repo doubles as a Homebrew tap:
#   brew tap sarat03/markquill https://github.com/sarat03/markquill
#   brew install --cask markquill
# The release job checks this version matches src-tauri/Cargo.toml.
cask "markquill" do
  arch arm: "mac_m_arm", intel: "mac_intelx64"

  version "0.1.2"
  # ponytail: no checksum, so a release only bumps the version; pin sha256 per arch before submitting to homebrew/cask
  sha256 :no_check

  url "https://github.com/sarat03/markquill/releases/download/v#{version}/MarkQuill_#{version}_#{arch}.dmg"
  name "MarkQuill"
  desc "Small, fast Markdown viewer and editor"
  homepage "https://github.com/sarat03/markquill"

  depends_on :macos

  app "MarkQuill.app"

  caveats <<~EOS
    MarkQuill isn't code-signed yet. If macOS blocks the first launch, open
    System Settings > Privacy & Security and click Open Anyway.
  EOS
end
