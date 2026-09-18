# MailAvatarSync

Give every sender in Apple Mail an avatar — real company logos and Gravatar photos where they exist, a clean coloured monogram everywhere else.

<img src="docs/sample-logo.png" width="72" align="top"> <img src="docs/sample-monogram.png" width="72" align="top">

## Why Apple Mail shows almost no avatars

Mail only has two sources for a sender image:

1. **A photo on a card in Contacts.** Nobody adds every newsletter and every colleague to Contacts, so this covers a handful of people at best.
2. **BIMI** brand logos, which require the sender to publish a DMARC-backed BIMI DNS record *and* buy a Verified Mark Certificate. Almost nobody does.

So in practice you get a grid of grey silhouettes. This script fills the gap by fetching a logo or photo for each sender and writing it to a Contacts card automatically.

## How it resolves an avatar

For each incoming sender, in order, stopping at the first hit:

1. **Gravatar** — a real photo the person chose for that address.
2. **Company logo**, walking from the full sending host up to the registrable domain. Bulk mail arrives from subdomains like `hei.email.kron.no` that have no website at all, so it tries `hei.email.kron.no`, then `email.kron.no`, then `kron.no`. At each level:
   - `/apple-touch-icon.png` and `/apple-touch-icon-precomposed.png` from the sender's own server — highest quality, typically 180px, and finds logos the icon aggregators have never indexed
   - DuckDuckGo's icon service
   - Google's favicon service
3. **A locally drawn monogram** — the sender's initials on a deterministic colour, rendered with Cocoa. No network, and it means *every* sender gets something.

Results are written as Contacts cards in a dedicated **MailAvatarSync** group, so they stay separate from the contacts you curate yourself. An existing card with a photo is never overwritten.

On a real inbox this took sender coverage from 1 card to 43, of which 39 resolved to a genuine logo.

## Requirements

macOS with Apple Mail. No dependencies — it uses `curl`, `sips` and `osascript`, all built in.

## Install

```sh
git clone https://github.com/torbjornlarssen/MailAvatarSync.git
cd MailAvatarSync
./install.sh
```

This compiles the script to `~/Library/Application Scripts/com.apple.mail/MailAvatarSync.scpt`, backing up any existing copy.

Then:

1. **Quit and reopen Mail.** It caches the compiled script, so edits do nothing until you restart it.
2. **Mail ▸ Settings ▸ Rules ▸ Add Rule.** Set the condition to match everything (e.g. *Every Message*, or `From` `contains` `@`), and the action to **Run AppleScript ▸ MailAvatarSync**.
3. Mail will ask for permission to control Contacts the first time the rule fires. Approve it. If you miss the prompt, enable it under **System Settings ▸ Privacy & Security ▸ Automation ▸ Mail ▸ Contacts**.

### Backfilling existing mail

Rules only fire on newly arriving messages. To process mail you already have, select the messages and press **⌥⌘L** (*Message ▸ Apply Rules*).

Allow a few seconds per previously unseen sender. Senders already in Contacts are skipped instantly, so this only costs you once.

### Re-resolving old monograms

If a sender got a monogram and you later want to retry for a real logo — for example after upgrading the script — run:

```sh
osascript backfill.applescript
```

This walks the MailAvatarSync group, retries the logo chain with the monogram fallback disabled, and replaces the image only when a real logo is found. It touches nothing outside that group.

## Configuration

Edit the properties at the top of `MailAvatarSync.applescript`, then re-run `./install.sh` and restart Mail.

| Property | Default | Effect |
|---|---|---|
| `targetGroupName` | `MailAvatarSync` | Contacts group the created cards go into |
| `useMonogramFallback` | `true` | Draw initials when no logo or photo is found |
| `probeSenderDomain` | `true` | Request `/apple-touch-icon.png` from the sender's own server |
| `verboseLogging` | `true` | Log every decision to `~/Library/Logs/MailAvatarSync.log` |
| `addNoteSignature` | `true` | Stamp created cards with a note saying where they came from |
| `freemailDomains` | Gmail, iCloud, … | Domains treated as individuals, so no company logo is attempted |

## Privacy

Be aware of what leaves your machine for each new sender:

- The address is **MD5-hashed** and sent to Gravatar.
- The sending **domain** is sent to DuckDuckGo and Google.
- With `probeSenderDomain : true`, a request goes to the **sender's own web server**, which reveals your IP address to them. It is not per-message like a tracking pixel, but if you use Mail Privacy Protection specifically to avoid this, set it to `false`.

Setting `probeSenderDomain : false` and commenting out the DuckDuckGo, Google and Gravatar lookups in `findAvatar` leaves you with monogram-only operation and zero outbound traffic.

Created contacts sync wherever your Contacts sync. If you would rather they stayed on this Mac, point Contacts at a local account before enabling the rule.

## Troubleshooting

**Nothing happens at all.** Check the log first:

```sh
tail -f ~/Library/Logs/MailAvatarSync.log
```

An empty or missing log means the rule never fired — confirm the rule exists, is enabled, and that you restarted Mail.

Note that the script also emits `logger` messages, but those are Info-level and are **not** persisted, so `log show` will never find them after the fact. Only `log stream` catches them live. The file is the one to read.

**Contacts errors in the log.** Mail needs automation permission: **System Settings ▸ Privacy & Security ▸ Automation ▸ Mail ▸ Contacts**.

**A sender still gets a monogram.** Some domains genuinely have no discoverable icon at any level. Add a photo to that card by hand; the script will never overwrite it.

## Credits

Based on [vladtvoeit/MailAvatarSync](https://github.com/vladtvoeit/MailAvatarSync) by **baxenko**, MIT licensed. That project established the approach: a Mail rule that fetches a sender avatar and writes it to Contacts.

This version is a substantial rewrite, prompted by the original's logo sources having gone offline:

- **`api.faviconkit.com` is a zombie** — it still answers `200 OK`, but returns a 1×1, 70-byte PNG for every domain.
- **`logo.clearbit.com` no longer resolves in DNS**, having shut down after the HubSpot acquisition.

With both dead, only Gravatar remained, which covers very few real senders. Replacing them with DuckDuckGo and Google, adding apple-touch-icon probing, walking up from the sending subdomain, and drawing a monogram fallback is what takes coverage from "almost nothing" to "everything".

Other changes: images are validated by pixel dimensions rather than file size (which is what let the 1×1 placeholder through unnoticed), senders on freemail domains are created as people rather than companies, logging goes to a file you can actually read, and name trimming and the MD5 helper are fixed.

## License

MIT — see [LICENSE](LICENSE). Original copyright © 2025 baxenko, retained.
