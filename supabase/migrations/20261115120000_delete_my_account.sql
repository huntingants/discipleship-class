-- A student can delete their own account and everything attached to it.
-- Teachers and app admins are excluded: deleting a teacher would delete a whole class, so that stays a manual step.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); r text;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select role into r from public.profiles where id = uid;
  if r is distinct from 'student' then raise exception 'only student accounts can be deleted here'; end if;
  if exists (select 1 from public.app_admins where user_id = uid) then raise exception 'only student accounts can be deleted here'; end if;
  -- rows that have no foreign key to the user
  delete from public.attendance where member_id = uid;
  delete from public.student_notes where student_id = uid or created_by = uid;
  -- profile, progress, journal, prayers, prayed, prep and push_subs go with the user (on delete cascade)
  delete from auth.users where id = uid;
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
