# Tokens Monitor

A small macOS menu bar app for checking Claude, Codex, and Grok Bot account limits. Every progress bar shows **percentage used**. The menu bar shows the highest recently verified percentage; the optional pinned card keeps the full view visible above ordinary windows.

## Data sources

| Card | Source | Notes |
| --- | --- | --- |
| Codex · OpenAI | Codex app-server `account/rateLimits/read` | Reads account percentages and reset timestamps. If unavailable, the latest local Codex session rate-limit record is shown as **stale**. |
| Claude · Anthropic | Signed-in Claude usage page in an embedded browser | Reads the current session and all-model weekly percentages shown by Claude. |
| Grok Bot · xAI | Signed-in Grok billing dashboard in an embedded browser | Reads weekly included usage for the shared Grok/Grok Bot pool and available extra credits when shown. |

The app refreshes every 90 seconds and when opened. WebKit retains the Claude and Grok sign-ins across app restarts. The last successful percentages and reset labels are saved locally and shown as stale until a fresh page reading arrives. Account pages are not refreshed while their sign-in window is open, so login forms are not interrupted. No account passwords or session cookies are written by this project; WebKit manages its own website data.

Claude and Grok account-page parsing depends on their page text. If either site changes, its card will show a connection or stale state until the parser is updated. The app does not substitute local token estimates for account usage.

## Build and run

Requires macOS 13 or later and Swift command line tools.

```sh
make bundle
open ClaudeWidget.app
```

The app appears in the menu bar. Use **Connect** on the Claude and Grok cards to sign in once through the app's embedded account page. Use the pin button to show or hide the floating desktop card. `make install` copies the bundle to `/Applications`.

The executable and bundle keep the existing `ClaudeWidget` name for compatibility; the visible app name is **Tokens Monitor**.

## Icons

The OpenAI and Anthropic card icons were exported from their installed official macOS apps. The xAI icon comes from the official `x.ai` favicon. They identify the services; this independent utility is not endorsed by the vendors.

## References

- [Codex app-server rate-limit method](https://learn.chatgpt.com/docs/app-server)
- [Claude shared usage limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)
- [Grok Bot shared weekly pool](https://docs.x.ai/x-subscription/grok-bot)
