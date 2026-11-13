# Database setup

These files are a copy of the Supabase database setup behind the app: the tables, the
security rules (row level security), the functions the app calls, and the sign-up trigger.
They were copied from the live project's migration history on 2026-11-13.

Run them in filename order on an empty Supabase project to rebuild the database
(Supabase CLI: `supabase db push`, or paste each file into the SQL editor).

Before running `20261113021900_create_teacher_invites.sql`, replace `ADMIN_EMAIL`
with the admin's email address. It is left out here because this repository is public.

The data itself (accounts, journals, prayers, progress) is not in here. Back that up
from the Supabase dashboard.
