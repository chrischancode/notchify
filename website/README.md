# notchify.online

Static site for Notchify: `index.html`, `styles.css`, `app.js` and `assets/`. No build step.

## Preview locally

```sh
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

## Deploy on Vercel

Build settings live in `vercel.json` (one at the repo root, one in `website/`), so the project works whether its **Root Directory** is the repo root or `website`. There is no install or build step; Vercel serves the files as they are. Don't add a build command in the dashboard — `vercel.json` overrides it anyway.

Download buttons link straight to the latest GitHub release (`releases/latest/download/Notchify.dmg` and `Notchify.zip`), so there is no `/api/download` route to maintain. Keep those two asset names when publishing a release.

## What the demo does

The drawer at the top of the page is interactive: tabs, Pomodoro countdown (shown in the notch "ears" when closed), play/pause, dropping real files on the shelf (they never leave the browser), the webcam mirror (only after the visitor clicks, nothing recorded) and notes saved to `localStorage`.
