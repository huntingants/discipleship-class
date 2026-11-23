# App checks

Run them before uploading a change (needs Node.js 18 or newer, nothing to install):

    node tests/run-all.js

They run the real app code from `index.html` with made-up data and a pretend database, so
nothing is sent to Supabase. They cover saving across two devices, loading lessons (first
visit, returning user, no connection), invite links, the admin card, which teacher actions
send notifications, live updates, and crash reports. They also check that every translated
lesson file has the same layout as its English file (see below).

## Translation layout check

    node tools/check-translation.js                         every translation listed in index.html
    node tools/check-translation.js data/mat-ohb.ceb.json   one file

A translation such as `data/mat-ohb.ceb.json` must match `data/mat-ohb.json` lesson for lesson:
same sections, minutes, block types, `h3` numbers and list lengths, the same memory verse, the
`read` / `readtog` / `verse` blocks unchanged, and the Bible references in brackets, such as
"(John 3:16)", kept in English in the same order, since they open the verse pop-ups. A
translation may leave lessons out; those show in English. It prints each problem with the
lesson, section and block number.

GitHub also runs them automatically on every push (see `.github/workflows/tests.yml`).
A green tick next to a commit on GitHub means they all passed; a red X means one failed,
and GitHub emails the repo owner.

## Crash reports

When the app hits an unexpected error on someone's device, it sends a short note to the
`client_errors` table: the error message, where in the code, the screen (for example `#shome`),
the browser and the app version. No names, journal text or prayers are sent. At most 10 notes
per visit, 20 an hour per person, and notes are deleted after 30 days. The app admin sees them
under Class → App admin → See app problems.
