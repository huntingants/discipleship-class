# Database setup

These files are a copy of the Supabase database setup behind the app: the tables, the
security rules (row level security), the functions the app calls, and the sign-up trigger.
They were copied from the live project's migration history on 2026-11-13.

Run them in filename order on an empty Supabase project to rebuild the database
(Supabase CLI: `supabase db push`, or paste each file into the SQL editor).

Before running `20261113021900_create_teacher_invites.sql`, replace `ADMIN_EMAIL`
with the admin's email address. It is left out here because this repository is public.

## Push notifications

`functions/notify` is the Edge Function that sends notifications to a class's students
(deploy it with `supabase functions deploy notify`). It reads its signing keys from the
`app_secrets` table, which only the server can read. On a new project, make a key pair
(for example `npx web-push generate-vapid-keys`), put the public key in `config.js` as
`push`, and store both keys:

    insert into public.app_secrets (name, value) values
      ('vapid_public', '<public key>'), ('vapid_private', '<private key>'),
      ('vapid_subject', 'https://github.com/huntingants/discipleship-class');

The private key is never in this repository.

## Data

The data itself (accounts, journals, prayers, progress) is not in here. Back that up
from the Supabase dashboard.
