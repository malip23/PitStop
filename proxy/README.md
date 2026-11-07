# PitStop Gemini proxy (Cloudflare Worker, free)

Keeps your Gemini API key on Cloudflare instead of inside the app. The app sends requests to the
Worker with a shared token; the Worker adds the key and forwards to Google.

## Deploy (about 5 minutes, free plan)

1. **Install Node.js** (needed for Cloudflare's `wrangler` tool):
   ```sh
   brew install node        # or download the LTS installer from https://nodejs.org
   ```
2. **Log in to Cloudflare** (creates a free account if you don't have one; opens a browser):
   ```sh
   cd proxy
   npx wrangler login
   ```
3. **Store your Gemini key as a secret** (paste the key from Google AI Studio when asked):
   ```sh
   npx wrangler secret put GEMINI_API_KEY
   ```
4. **Create an app token** so only your app can use the Worker:
   ```sh
   openssl rand -hex 24          # copy the output
   npx wrangler secret put APP_TOKEN   # paste it
   ```
5. **Deploy:**
   ```sh
   npx wrangler deploy
   ```
   It prints a URL like `https://pitstop-gemini-proxy.<your-subdomain>.workers.dev`.
6. **Check it:** open `https://pitstop-gemini-proxy.<your-subdomain>.workers.dev/health` in a
   browser. It should say `"keyConfigured": true`.
7. **Point the app at it:** in `Secrets.xcconfig` (project root, git-ignored) add the host
   **without** `https://` (in .xcconfig files `//` starts a comment) and the token:
   ```
   AI_PROXY_HOST = pitstop-gemini-proxy.<your-subdomain>.workers.dev
   AI_PROXY_TOKEN = <the token from step 4>
   ```
   Rebuild. Settings → AI → Connection should say **Cloudflare Worker**.

Once the Worker works you can remove `GEMINI_API_KEY` from `Secrets.xcconfig`, so the key is no
longer bundled in the app at all.

## Notes
- Allowed models are listed at the top of `src/index.js`; keep them in sync with `AIConfig.swift`.
- Local testing: put `GEMINI_API_KEY=...` and `APP_TOKEN=...` in `proxy/.dev.vars` (git-ignored)
  and run `npx wrangler dev`.
- Free plan: 100,000 Worker requests/day, far more than the Gemini free tier allows.
