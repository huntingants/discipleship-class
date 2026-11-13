-- Fix sign-up after the teacher-invite change:
--  * co-leaders join with their co-leader code again (no invite needed); only teachers
--    starting a new class need an invite
--  * the admin is listed in app_admins instead of by email inside the functions
--  * functions get a fixed search_path, and the invites table loses grants it never needed
--
-- After running this on a new project, add the admin once:
--   insert into public.app_admins (user_id) select id from auth.users where email = 'ADMIN_EMAIL';

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
revoke all on public.app_admins from public, anon, authenticated;

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.app_admins where user_id = auth.uid()) $$;
revoke all on function public.is_app_admin() from public, anon;
grant execute on function public.is_app_admin() to authenticated;

-- invites: only the admin reads or creates them, and only through these rules
drop policy if exists "Admin can read invites" on public.teacher_invites;
drop policy if exists "Admin can create invites" on public.teacher_invites;
create policy teacher_invites_admin_read on public.teacher_invites for select to authenticated using (public.is_app_admin());
revoke all on public.teacher_invites from public, anon, authenticated;
grant select on public.teacher_invites to authenticated;

create or replace function public.create_teacher_invite() returns text
language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if not public.is_app_admin() then raise exception 'Only the admin can create teacher invites'; end if;
  insert into public.teacher_invites (created_by) values (auth.uid()) returning token into tok;
  return tok;
end $$;
revoke all on function public.create_teacher_invite() from public, anon;
grant execute on function public.create_teacher_invite() to authenticated;

create or replace function public.validate_teacher_invite(token text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.teacher_invites t
    where t.token = btrim(validate_teacher_invite.token) and t.used_by is null
  )
$$;
revoke all on function public.validate_teacher_invite(text) from public;
grant execute on function public.validate_teacher_invite(text) to anon, authenticated;

-- sign-up: a new teacher needs an unused invite; a co-leader needs a right co-leader code; a student needs nothing more
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  lcode text := upper(btrim(coalesce(meta->>'leader_code', '')));
  r text := case when meta->>'role' = 'teacher' then 'teacher' else 'student' end;
  mat text := coalesce((select id from public.materials where id = meta->>'material'), 'disciple');
  inv_token text := btrim(coalesce(meta->>'invite_token', ''));
  cid uuid;
begin
  if r = 'teacher' and lcode <> '' then
    select id into cid from public.classes where leader_code = lcode;
    if cid is null then raise exception 'That co-leader code is not right'; end if;
  elsif r = 'teacher' then
    if inv_token = '' then raise exception 'Teacher accounts require an invitation'; end if;
    update public.teacher_invites set used_by = new.id, used_at = now()
    where token = inv_token and used_by is null;
    if not found then raise exception 'Invalid or already used invite token'; end if;
    insert into public.classes (name, teacher_id, join_code, material)
    values (coalesce(nullif(btrim(meta->>'class_name'), ''), 'Discipleship Class'), new.id, public.gen_code(), mat)
    returning id into cid;
  else
    select id into cid from public.classes where join_code = upper(btrim(coalesce(meta->>'join_code', '')));
  end if;
  insert into public.profiles (id, name, role, class_id)
  values (new.id, coalesce(nullif(btrim(meta->>'name'), ''), 'Friend'), r, cid);
  if r = 'teacher' and cid is not null then
    insert into public.teacher_classes (teacher_id, class_id) values (new.id, cid) on conflict do nothing;
  end if;
  insert into public.progress (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
