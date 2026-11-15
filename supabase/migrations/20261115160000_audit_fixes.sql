-- Audit fixes (2026-11-15)
-- 1. Test notifications have no class, but push_log required one, so the log row was never written
--    and the "one test every 30 seconds" limit never worked. Also record how many sends failed.
alter table public.push_log alter column class_id drop not null;
alter table public.push_log add column if not exists failed int not null default 0;

-- 2. Deleting a teacher's account in the dashboard was blocked by the invite they used or made.
alter table public.teacher_invites alter column created_by drop not null;
alter table public.teacher_invites drop constraint teacher_invites_created_by_fkey,
  add constraint teacher_invites_created_by_fkey foreign key (created_by) references auth.users(id) on delete set null;
alter table public.teacher_invites drop constraint teacher_invites_used_by_fkey,
  add constraint teacher_invites_used_by_fkey foreign key (used_by) references auth.users(id) on delete set null;
