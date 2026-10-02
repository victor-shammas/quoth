# Quoth website (GitHub Pages)

The marketing, support and privacy pages, in the same plain format as Plainview's and Gaugeline's: HTML and one stylesheet, no build step, external fonts, scripts or trackers, in the espresso and amber palette of the app icon.

| File | Published URL |
|---|---|
| `index.html` | https://victorshammas.com/quoth/ (Marketing URL) |
| `support.html` | https://victorshammas.com/quoth/support.html (Support URL; `#remove` explains uninstalling) |
| `privacy.html` | https://victorshammas.com/quoth/privacy.html (Privacy Policy URL) |
| `style.css`, `icon.png`, `favicon.png`, `apple-touch-icon.png` | assets |
| `.nojekyll` | tells Pages to serve files as-is |

## Publishing

The GitHub Pages user site (`victor-shammas.github.io`) has the custom domain `victorshammas.com`, so a public repo named `quoth` with Pages on is served at `/quoth/`. In the repo: Settings › Pages › Deploy from a branch › `main`, folder `/docs`. No `CNAME` file. The developer docs in this folder (`architecture.md`, `decisions/`) are served too, as plain files, which is harmless.

## Before launch

- Replace the "Coming soon" span in `index.html` with the App Store link (the HTML comment there has it), once the app record exists.
- Link the direct download (GitHub Releases) in the "Two ways to get Quoth" section once there is a release.
- Keep the privacy policy in step with the App Privacy answers in App Store Connect (Data Not Collected), and update its effective date when it changes.
- Regenerate the icons after an icon change: `sips -s format png -z 256 256 assets/quoth-icon.png --out icon.png`, `-z 64 64` for `favicon.png`, and an opaque 180 px `apple-touch-icon.png`.
