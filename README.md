# discourse-club-teams

Keeps one topic updated with recent results and upcoming fixtures for a
club's *other* teams — women's side, reserves, youth — the ones the big
football APIs' free tiers don't cover.

Nothing here is club-specific: it's a list of team ids, display labels
and which provider to ask.

Licensed GPLv2, matching Discourse.

---

## Providers

| Provider | Key | Current season | Covers |
| --- | --- | --- | --- |
| `espn` | none | yes | ESPN's public API — see the slug list below |
| `api_football` | required | **paid plans only** | ~1,200 leagues |

**ESPN is the default and needs no registration at all.** Its API is
undocumented and unsupported, so every field is read defensively and a
missing one degrades rather than raises.

**API-Football's free plan cannot drive this plugin.** It covers every
competition and endpoint, but only for historical seasons — currently
2022–2024. Ask for the season in progress and it returns HTTP 200 with
an empty result and `"errors": {"plan": "Free plans do not have access
to this season…"}`. The $19/month Pro plan removes the limit. The
provider is kept for leagues ESPN doesn't carry.

### What ESPN carries for Spain

| Slug | Competition |
| --- | --- |
| `esp.1` | LALIGA |
| `esp.2` | LALIGA 2 |
| `esp.copa_del_rey` | Copa del Rey |
| `esp.super_cup` | Supercopa |
| `esp.w.1` | **Liga F** |
| `esp.copa_de_la_reina` | **Copa de la Reina** |

There is **no Primera Federación**, so club B teams — Sevilla Atlético
and the like — are not available from ESPN at any price. ESPN returns an
empty body rather than a 404 for a slug it doesn't carry, which is why
`find_teams.rb` calls that case out by name.

---

## Setup

**1. Find your team id.**

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/find_teams.rb esp.w.1 sevilla"
```

Names in the API rarely match what you'd guess — the Sevilla women's
side is simply "Sevilla", id `21424`.

**2. Confirm the data is really there** before trusting it:

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/probe.rb espn 21424 esp.w.1"
```

This prints the exact fields the digest reads and names the failure in
words if there is one. Any `nil` where a value is expected means the
shape has drifted.

**3. Configure.** Admin → Settings → `club_teams`:

| Setting | Notes |
| --- | --- |
| `club_teams_enabled` | Off by default. |
| `club_teams_teams` | `Label\|provider\|id\|league;league`, comma separated. |
| `club_teams_topic_id` | **Required.** The topic the post lives in. |
| `club_teams_heading` | Heading at the top of the post. |
| `club_teams_api_key` | Only for `api_football`. |
| `club_teams_recent_count` | Results per team. Default 3. |
| `club_teams_upcoming_count` | Fixtures per team. 0 hides the section. |
| `club_teams_back_days` | How far back to look. Default 150. |
| `club_teams_forward_days` | How far ahead to look. Default 90. |
| `club_teams_timezone` | Default `Europe/Madrid`. |

The default `club_teams_teams` is already Sevilla Femenino across Liga F
and the Copa de la Reina:

```
Femenino|espn|21424|esp.w.1;esp.copa_de_la_reina
```

The old `Label:id` form from v0.1 still parses, and is treated as
`api_football`.

**4. Publish** without waiting for the job:

```bash
su discourse -c "RAILS_ENV=production bin/rails runner \
  plugins/discourse-club-teams/script/sync_now.rb"
```

---

## Behaviour

- Runs every 6 hours; **one request per league per team per run**. ESPN
  publishes no rate limit but asks for restraint, so the default cadence
  is deliberately modest.
- Posts once, then **edits that same post** thereafter — the topic gets
  one living summary, not a pile of updates.
- **Only writes when something changed**, compared by fingerprint.
- **Edits don't bump the topic**, so a season of results won't dominate
  Latest.
- **If every team returns nothing, the existing post is left alone.** A
  total wipeout almost always means an outage or a misconfiguration
  rather than genuinely empty seasons, and replacing good content with
  "no fixtures found" would be worse than doing nothing. The reason is
  logged.
- A team with no fixtures in the window is dropped entirely rather than
  left as a bare heading.
- Postponed and cancelled fixtures are excluded from "next up".

### Two things that bite, both handled

**Win/loss is decided by score, not by the winner flag.** ESPN sets
`winner: false` on *both* sides of a draw, so trusting that flag alone
turns every draw into a defeat. Which side is "us" is decided by team
id, never by name — the label is a display string you choose
("Femenino") and generally won't resemble the API's own name.

**A scheduled match reports its score as `"0"`, not null.** Read
unconditionally, every upcoming fixture renders as 0–0. Scores are only
read once a match is live or finished.

---

## Checks

`script/check.rb` runs the parsing and rendering layers against a
captured ESPN response — no Rails, no network, no database:

```bash
ruby script/check.rb
```

44 checks covering status mapping, draw detection, phantom scores,
setting parsing and table rendering. Worth running before any rebuild.
