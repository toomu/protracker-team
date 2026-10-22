# ProTracker (hosted)

ProTracker as its own web app at **https://team.indexhomes.in/** (https://protracker.indexhomes.in/ forwards there, after saving any offline changes left on that device), with sign-in by email and your tasks saved in Supabase. It's the same page as the claude.ai artifact (`tasks.html`), built for hosting by `build.py`.

- `build.py`: wraps `../tasks.html` into `index.html`. It adds the install tags, supabase-js and the service worker at the `<!--hosted-head…-->` marker, and copies the files below.
- `deploy.sh "What changed"`: builds it into both public repos and pushes: `toomu/protracker-app` (protracker.indexhomes.in) and `toomu/protracker-team` (team.indexhomes.in, the old team app's address). GitHub Pages serves them.
- `CNAME`: protracker.indexhomes.in (deploy.sh writes each repo's own).
- `manifest.webmanifest`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`: the Index Homes gold "1" on navy. Add to Home Screen opens it full screen.
- `sw.js`: opens offline (the app's files network-first; supabase-js and fonts cache-first; never touches supabase.co).
- `schema.sql`: the `public.pt_docs` table, where each person's data lives (only they can read or change it).
- `functions/handwriting/index.ts`: the Edge Function `handwriting`, which reads the writing pad with Claude. It is deployed with JWT verification on.

## How it works

- **Sign in:** you type your email, then the 8-digit code from the email. Only the owner and the emails in the owner's People list can sign in: the sign-in hook `pt_access_token_hook` refuses everyone else, and the access rules block them as a backstop (see `schema.sql`). Each person gets their own private ProTracker.
- **Storage:**
  - One row per document in `pt_docs`, the same shape as the artifact's: task documents keyed by task id, plus `_people`, `_tags`, `_tagcats` and `_team`.
  - Changes show at once and save in the background. Offline, they wait on the device and are sent when you're back.
  - Other devices' changes arrive live.
- **Team ticks:** read straight from `team_tasks` (the owner sees every pushed task); no Supabase connector needed.
- **Handwriting:**
  - Only for the emails in `ALLOWED` in the function. The page asks the function (`{check: true}`) whether to show the pad, so the list isn't in the public page, and the function refuses anyone else.
  - It needs the secret `ANTHROPIC_API_KEY`: Supabase dashboard → Edge Functions → Secrets.
- **Assigning:** the owner, and Full members the owner allows ("Can assign tasks"), keep the lists of the people they assign to in step. Each assigner only touches the tasks they created. Every assigned task records who assigned it (`assigned_by`, set by the database) and shows "From <name>".
- **Team members:** everyone who isn't the owner gets Simple (one list: assigned tasks plus their own) or Full (all of ProTracker plus an Assigned tab), set per person by the owner in People and stored in `pt_members` (see `schema.sql`). Their own tasks are private. Notifications for new tasks are handled by `sw.js`, which keeps the old team app's subscriptions working at team.indexhomes.in.
- **Team lists:** the owner's ProTracker keeps each person's list in the team app in step by itself, with no Publish button. It writes straight to `team_tasks` whenever an assigned task changes and sends notifications for new ones; the People sidebar shows the state. Ticks come back live.

## Setup (done once)

1. In Supabase, run `schema.sql`, deploy `functions/handwriting` as `handwriting`, and add the secret `ANTHROPIC_API_KEY`.
2. Go to Authentication → URL Configuration and add `https://protracker.indexhomes.in` under Redirect URLs, so the link in the sign-in email comes back here (the code works without it).
3. In DNS (GoDaddy), add a CNAME record: `protracker` → `toomu.github.io`.
4. In the repo's Pages settings, once the certificate is issued, turn on Enforce HTTPS.
5. Turn on the sign-in hook: Authentication → Hooks → Customize Access Token (JWT) Claims → Postgres → schema `public`, function `pt_access_token_hook`.
