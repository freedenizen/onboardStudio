# Uploading to YouTube

OverlayGen can upload an export straight to YouTube (**Export ▸ Upload to YouTube…**, **Project ▸
Upload Video to YouTube…**, or `overlaygen upload`). Google requires every app to identify itself
with its own OAuth client, and an open-source app cannot ship a shared one, so a one-time setup is
needed:

1. Open <https://console.cloud.google.com/>, create a project (any name) and enable the
   **YouTube Data API v3** under *APIs & Services ▸ Library*.
2. Under *APIs & Services ▸ OAuth consent screen* choose **External**, fill in the app name and
   your e-mail, add the scope `https://www.googleapis.com/auth/youtube.upload`, and add your
   Google account as a test user (a consent screen in "Testing" is enough for personal use).
3. Under *Credentials ▸ Create credentials ▸ OAuth client ID* pick **TVs and Limited Input
   devices**. Copy the client ID and client secret.
4. In OverlayGen open **Settings ▸ YouTube** and paste both. (Google documents the secret of an
   installed app as not confidential; OverlayGen keeps it in preferences and the sign-in token in
   the keychain.) For the CLI pass `--client-id/--client-secret` or set
   `OVERLAYGEN_YT_CLIENT_ID` / `OVERLAYGEN_YT_CLIENT_SECRET`; its token lives in
   `~/Library/Application Support/OverlayGen/youtube-token.json` (owner-only permissions).

## Signing in

The first upload shows a short code and a link (`google.com/device`). Open the link, enter the
code, approve the `youtube.upload` scope; the app notices within a few seconds. The token is
refreshed automatically; **Sign Out** (upload sheet or Settings) forgets it.

## Uploading

Title, description, tags and privacy (private / unlisted / public; category "Sports") are set in
the upload sheet. The file is sent with YouTube's resumable protocol in 8 MB chunks; a dropped
connection is retried from the last byte the server confirms (up to five times with back-off), so
long uploads survive a flaky link. The sheet shows the watch link when the upload completes.

```sh
swift run overlaygen upload out.mp4 --title "Sonoma lap 3" --privacy unlisted --tags "sonoma,track day"
swift run overlaygen upload --sign-out
```

## Quota

The YouTube Data API grants 10,000 units per project per day; an upload costs about 1,600, so
roughly six uploads a day per Google Cloud project without asking Google for more.
