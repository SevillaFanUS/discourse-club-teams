# discourse-club-teams

Keeps one topic updated with recent results and upcoming fixtures for a
club's *other* teams — women's side, reserves, youth — the ones the big
football APIs' free tiers don't cover.

Uses [API-Football](https://www.api-football.com/) (api-sports.io), whose
free tier covers ~1,200 leagues at 100 requests/day. This plugin spends
one request per team per run.

Nothing here is club-specific: it's a list of team ids and display
labels.

Licensed GPLv2, matching Discourse.

---

## Why a second API

football-data.org's free tier covers twelve competitions — the big five
leagues and a handful of cups. It has no Liga F, no Primera Federación,
no regional divisions. If you're already using it for the first team,
this plugin sits alongside rather than replacing it.

---

## Setup

**1. Get a key** at [api-sports.io](https://api-sports.io/) and set
`club_teams_api_key`.

**2. Find your team ids.** Names in the API rarely match what you'd
guess — the women's side may be "Sevilla FC W", the reserves "Sevilla
Atletico" without the accent:

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/find_teams.rb Sevilla"
```

Costs one request per search term and prints ids, names and countries.

**3. Confirm the data is really there** before trusting it. Coverage of
lower divisions varies, and an empty season is indistinguishable from a
wrong id unless you look:

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/probe.rb 1234"
```

This prints the exact fields the plugin reads. Any `nil` means the shape
differs from what's expected and the digest needs adjusting.

**4. Configure.** Admin → Settings → `club_teams`:

| Setting | Notes |
| --- | --- |
| `club_teams_enabled` | Off by default. |
| `club_teams_api_key` | From api-sports.io. |
| `club_teams_teams` | `Label:id` pairs, e.g. `Femenino:1234,Sevilla Atlético:5678`. |
| `club_teams_topic_id` | **Required.** The topic the post lives in. |
| `club_teams_season` | Blank = auto-detect (June rollover). |
| `club_teams_recent_count` | Results per team. Default 3. |
| `club_teams_upcoming_count` | Fixtures per team. 0 hides the section. |
| `club_teams_timezone` | Default `Europe/Madrid`. |

**5. Publish** without waiting for the job:

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/sync_now.rb"
```

---

## Behaviour

- Runs every 6 hours; **one request per team per run** (12/day for three
  teams, against a 100/day free tier).
- Posts once, then **edits that same post** thereafter — the topic gets
  one living summary, not a pile of updates.
- **Only writes when something changed**, compared by fingerprint.
- **Edits don't bump the topic**, so a season of results won't dominate
  Latest.
- **If every team returns nothing, the existing post is left alone.** A
  total wipeout almost always means a bad key or exhausted quota rather
  than genuinely empty seasons, and replacing good content with "no
  fixtures found" would be worse than doing nothing.
- Postponed and cancelled fixtures are excluded from "next up" rather
  than shown as upcoming.

### Win/loss is decided by team id

Not by name. The label is a display string you choose ("Femenino") and
generally won't resemble the API's own team name ("Sevilla FC W"), so
matching on it silently yields blank outcomes. Draws are read from
API-Football's per-side `winner` flag being null on a finished match,
which handles them without inferring from goals.

---

## Notes

- The API returns **HTTP 200 with a populated `errors` field** for an
  invalid key or an out-of-plan request, so a 2xx alone doesn't mean
  success. The client checks both.
- Remaining daily quota is read from the response headers and printed by
  `find_teams.rb`.
- Very low divisions (regional leagues) may not be covered at all. Check
  with `probe.rb` before adding a team; if nothing comes back, that
  competition isn't in the dataset and no amount of configuration will
  help.
