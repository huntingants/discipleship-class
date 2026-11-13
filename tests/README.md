# App checks

Run them before uploading a change (needs Node.js 18 or newer, nothing to install):

    node tests/run-all.js

They run the real app code from `index.html` with made-up data and a pretend database, so
nothing is sent to Supabase. They cover saving across two devices, loading lessons (first
visit, returning user, no connection), invite links, the admin card, which teacher actions
send notifications, and live updates.
