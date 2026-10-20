# ProTracker Team

A hosted companion to ProTracker. You push the tasks you assigned someone in ProTracker, and they sign in here with their email to see them as a simple list and tick them off. They can also add tasks of their own; those stay in the team app and never go back to ProTracker.

- `index.html`: the whole app, a static page that runs on any static host.
- `schema.sql`: the database tables and privacy rules for Supabase.
- `demo-client.js`: an in-browser stand-in for Supabase, used only by demo mode (`?demo`).
- `sw.js`: lets the app open offline and shows notifications.
- `functions/push/index.ts`: the Supabase Edge Function that sends notifications (deploy it as `push` with JWT verification on; it makes its own signing keys).
- `deploy.sh`: publishes this folder to GitHub Pages (live at https://team.indexhomes.in/).
- `CNAME`: the custom domain GitHub Pages serves the app on.
- `manifest.webmanifest`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, `favicon.png` (the Index Homes gold "1" logo on dark navy); `logo.png` is the same logo, trimmed and transparent, shown beside the title: let phones install it with **Add to Home screen** as a full-screen app with its own icon (no browser address bar).

## Try it locally (demo mode)

No accounts needed. From the project folder, run `python3 -m http.server 8000`, then open:
- http://localhost:8000/tasks.html for a local copy of ProTracker. Its tasks are saved in this browser, separate from your claude.ai app. Served from localhost, its Publish box points at the local demo.
- http://localhost:8000/team/?demo for the team app in demo mode (`demo-client.js`). Sign in with any email and the code `123456`; `owner@demo.test` is the owner. Each tab can be signed in as a different person, and changes show up in the other tabs.

Demo data lives only in this browser. Sign-in emails and privacy are only real once Supabase is set up.

## One-time setup

1. **Create a Supabase project** (free) at https://supabase.com.
2. **Create the database**: in the dashboard, go to SQL Editor → New query, paste all of `schema.sql`, and Run.
3. **Turn on sign-in codes in the emails.** Go to Authentication → Email Templates. In both **Magic Link** and **Confirm signup**, add a line such as `Your code: {{ .Token }}`. The link in the email keeps working too.
4. **Set where sign-in links return.** Go to Authentication → URL Configuration and set **Site URL** to the address where you host `index.html`. Add the same address under Redirect URLs.
5. **Connect the page.** Go to Project Settings → API, copy the **Project URL** and the **anon public** key, and paste them into `SUPABASE_URL` and `SUPABASE_ANON_KEY` near the top of the script in `index.html`. The anon key is meant to be public; the privacy rules in `schema.sql` protect the data.
6. **Host `index.html`** on any static host (GitHub Pages, Cloudflare Pages, Netlify) over https.
7. **Make yourself the owner.** Open the app and sign in once with your email. Then run this in the SQL Editor:
   ```sql
   insert into public.admins (user_id) select id from auth.users where email = 'you@example.com';
   ```
   Reload the app, and you'll see the People list and the owner tools.
8. **Notifications (optional).** Deploy `functions/push/index.ts` as the Edge Function `push` (Supabase dashboard → Edge Functions, or the CLI: `supabase functions deploy push`). Nothing else to configure: it creates its key pair on first use.
9. **Point ProTracker at it.** In ProTracker's `tasks.html`, set `TEAM_URL` to the hosted address and republish the artifact.

Supabase's built-in email sender only sends a few emails per hour, which is fine for a handful of people. For more, add your own SMTP under Authentication → SMTP Settings.

## On phones

- Add it to the home screen (Chrome: ⋮ → Install app; Safari: Share → Add to Home Screen) and it opens full screen like an app.
- Sign in with the code from the email. In the home-screen app, don't tap the email's link: it signs in the browser, not the app.
- Tap the list's title (e.g. "My tasks ⌄") to pick a tag (or, for the owner, a person) from a sheet at the bottom.
- Swipe a task right to tick it, left to delete one you added. Every tick or delete can be undone from the bar that appears.
- Pull down to refresh in the home-screen app.
- Notifications: tap **Turn on** on the card above the list (or in the menu under your initial) to get a notification when new tasks are shared with you. On iPhone this needs iOS 16.4+ and the app added to the Home Screen; in Safari itself it isn't possible.
- Works offline: it opens with your last list, and ticks and new tasks are sent when you're back online.

## Publishing

1. In ProTracker, go to People and give each person who uses the team app their email.
2. Tap **Publish to team** in ProTracker's top bar (a paper-plane icon on the Tasks view and on phones), on any page. One tap publishes to everyone with an email; people without one are listed as not included.
3. The team app opens in a new tab and applies the push right away, for each person. Sign in as the owner first if it asks.
4. If the new tab doesn't open, tap **Copy link** in ProTracker instead. Then, in the team app, open "Paste a publish link from ProTracker" and paste it there.

What a push does, for each person in it:
- Their list becomes exactly the tasks assigned to them in ProTracker (Repo excluded), in ProTracker's order, with subtasks right after their parent.
- New tasks are added; existing ones take any new name and tags. Ticks they made are kept.
- If they got new tasks and turned notifications on, each of their phones gets a notification ("3 new tasks from ProTracker" with the first titles). The status line says how many devices were notified.
- Tags show as coloured chips on each task, and a Tags column on the left (like ProTracker's Tree view) shows one tag's tasks at a time.
- Tasks no longer assigned to them are removed.
- Tasks they added themselves are never changed or removed by a push.

## Team ticks in ProTracker

When a team member ticks a task you pushed, ProTracker can show it as a green "✓ name" pill on that task, separate from your own tick.

ProTracker reads the ticks by itself through your Supabase connector in claude.ai: the first time, it asks you to allow Supabase for the page (or tap **Connect Supabase** under People → Team ticks). After that it checks when you open it and every minute while it's open. It only ever runs one read query: which pushed tasks are ticked, by whom and when.

There is no manual sync. Without the Supabase connector (not connected, or ProTracker opened outside claude.ai), ProTracker keeps showing the last ticks it read.

## Who can do what

The database enforces these rules, not the page:
- **Each person** sees only tasks for their own email. They can tick tasks, add their own, and delete the ones they added (not the pushed ones). They can't touch anyone else's tasks or move a task into someone else's list. The owner can see the tasks they add.
- **The owner** (anyone in `public.admins`) sees and changes everyone's tasks and publishes.
