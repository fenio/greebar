#!/bin/zsh
# Publishes a GitHub release and updates the cask in fenio/homebrew-tap.
# Usage: ./release.sh <version>    e.g. ./release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version>}
TAG="v$VERSION"
ZIP="build/GreeBar-$VERSION.zip"

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean"; exit 1; }

echo "$VERSION" > VERSION
./build-app.sh "$VERSION"
rm -f "$ZIP"
ditto -c -k --keepParent build/GreeBar.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

if [[ -n "$(git status --porcelain VERSION)" ]]; then
    git commit -m "Release $VERSION" VERSION
fi
git tag "$TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ZIP" --title "GreeBar $VERSION" --generate-notes

TAP=$(mktemp -d)
gh repo clone fenio/homebrew-tap "$TAP" -- -q
cat > "$TAP/Casks/greebar.rb" <<CASK
cask "greebar" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/fenio/greebar/releases/download/v#{version}/GreeBar-#{version}.zip"
  name "GreeBar"
  desc "Menu bar controller for Gree air conditioners"
  homepage "https://github.com/fenio/greebar"

  depends_on macos: ">= :sonoma"

  app "GreeBar.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/GreeBar.app"]
  end

  uninstall quit: "local.greebar.GreeBar"

  zap trash: "~/Library/Preferences/local.greebar.GreeBar.plist"
end
CASK
git -C "$TAP" add Casks/greebar.rb
git -C "$TAP" commit -m "greebar $VERSION"
git -C "$TAP" push
rm -rf "$TAP"
echo "Released $TAG"
