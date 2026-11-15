# App checks

Run them before uploading a change (needs Node.js 18 or newer, nothing to install):

    node tests/run-all.js

They run the real app code from `index.html` with made-up data and a pretend database, so
nothing is sent to Supabase. They cover saving across two devices, loading lessons (first
visit, returning user, no connection), invite links, the admin card, which teacher actions
send notifications, live updates, and crash reports.

GitHub also runs them automatically on every push (see `.github/workflows/tests.yml`).
A green tick next to a commit on GitHub means they all passed; a red X means one failed,
and GitHub emails the repo owner.

## Crash reports

When the app hits an unexpected error on someone's device, it sends a short note to the
`client_errors` table: the error message, where in the code, the screen (for example `#shome`),
the browser and the app version. No names, journal text or prayers are sent. At most 10 notes
per visit, 20 an hour per person, and notes are deleted after 30 days. The app admin sees them
under Class → App admin → See app problems.
