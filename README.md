# Chapter Player

A small static web app for playing long YouTube tracks by chapter:
sign in with your Google account, browse your playlists (public, unlisted,
or private), pick a video, and it parses the chapter timestamps out of the
description so you can jump between chapters or loop just one — without
downloading anything.

## 1. Create a Google Cloud OAuth client

1. Go to [console.cloud.google.com](https://console.cloud.google.com) and create a project (or use an existing one).
2. **APIs & Services > Library** — enable **YouTube Data API v3**.
3. **APIs & Services > OAuth consent screen**:
   - User type: External.
   - Publishing status: leave it in **Testing**.
   - Add scope `https://www.googleapis.com/auth/youtube.readonly`.
   - Under **Test users**, add your own Google account email. While the app
     is in Testing mode, only accounts listed here can sign in — that's
     fine for a personal tool and avoids Google's app-verification review.
4. **APIs & Services > Credentials > Create credentials > OAuth client ID**:
   - Application type: **Web application**.
   - Authorized JavaScript origins: add `http://localhost:8000` (or
     whatever port you'll run the local server on).
5. Copy the generated **Client ID** into [`config.js`](config.js), replacing
   `YOUR_CLIENT_ID.apps.googleusercontent.com`.

No API key is needed — the OAuth access token authorizes all the API calls
this app makes.

## 2. Run it locally

Google's sign-in library refuses to run from a `file://` page, so serve the
folder over HTTP:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000` in your browser and click **Sign in with
Google**.

## 3. Using it on your phone

Google's sign-in library only allows `http://` origins for `localhost` —
everywhere else needs `https://`. So to use this from your phone, deploy the
folder to any free static host with HTTPS (GitHub Pages, Netlify, Vercel all
work with zero backend, since this app is 100% static files). Then add that
site's URL as an additional **Authorized JavaScript origin** on the OAuth
client (step 4 above) and put it in your phone's browser or add it to your
home screen. Ask me if you'd like help setting up one of these.

## How chapters are detected

YouTube itself doesn't expose chapters as structured data — it infers them
from timestamp lines in the video description (e.g. `14:22 Midnight drift`
or `Midnight drift - 14:22`), and so does this app. If a video's description
doesn't have at least two timestamp lines, no chapters will show.

## Notes

- **Playlists tab** lists playlists you own (`mine=true`) — not "Liked
  videos" or playlists someone else made that you've saved.
- **Now playing tab** also accepts any YouTube URL or bare video ID pasted
  directly, so you're not limited to your own playlists.
- API usage here is tiny (a handful of calls per session against a 10,000
  units/day quota), so you won't come close to any limits with personal use.
- Your OAuth access token lasts about an hour; the app will silently prompt
  you to reconnect via the sign-in button if a call fails after it expires.
