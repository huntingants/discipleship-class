-- the teaching materials a class can choose. week_offset keeps each material's progress, journals and attendance apart.
create table public.materials (
  id text primary key check (id ~ '^[a-z0-9_-]{1,30}$'),
  label text not null,
  week_offset int not null unique check (week_offset >= 0 and week_offset % 1000 = 0)
);
insert into public.materials (id, label, week_offset) values ('disciple', 'Disciple Series', 0), ('ohb', 'OHB Series', 1000);
alter table public.materials enable row level security;
create policy materials_read on public.materials for select to authenticated using (true);
revoke all on public.materials from public, anon;
grant select on public.materials to authenticated;

alter table public.classes add column material text not null default 'disciple' references public.materials(id);
grant select (material) on public.classes to authenticated;
grant update (material) on public.classes to authenticated;

-- lesson and week numbers are now stored as offset + number, so the old 1..63 limits go
alter table public.journal drop constraint journal_lesson_check;
alter table public.journal add constraint journal_lesson_check check (lesson >= 1 and lesson <= 9999);
alter table public.prep drop constraint prep_lesson_check;
alter table public.prep add constraint prep_lesson_check check (lesson >= 1 and lesson <= 9999);
alter table public.attendance drop constraint attendance_week_check;
alter table public.attendance add constraint attendance_week_check check (week >= 1 and week <= 9999);

-- switching material restarts the class at lesson 1 and closes check-in
create or replace function public.classes_checkin_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.material is distinct from old.material then
    new.week := 1; new.checkin_open := false;
  end if;
  if new.checkin_open and not coalesce(old.checkin_open, false) then
    new.checkin_at := now();
  end if;
  if new.week is distinct from old.week then
    new.checkin_open := false;
  end if;
  return new;
end $$;

-- check-in records the class's current week for its material
create or replace function public.check_in() returns int
language plpgsql security definer set search_path = public as $$
declare cid uuid; wk int; open_ boolean; at_ timestamptz; off_ int;
begin
  select c.id, c.week, c.checkin_open, c.checkin_at, m.week_offset into cid, wk, open_, at_, off_
  from public.classes c join public.profiles p on p.class_id = c.id join public.materials m on m.id = c.material
  where p.id = auth.uid() and p.role = 'student';
  if cid is null then raise exception 'You are not in a class'; end if;
  if not open_ or (at_ is not null and at_ < now() - interval '4 hours') then
    raise exception 'Check-in is not open yet';
  end if;
  wk := wk + off_;
  insert into public.attendance (class_id, week, member_id) values (cid, wk, auth.uid()) on conflict do nothing;
  return wk;
end $$;
revoke all on function public.check_in() from public, anon;
grant execute on function public.check_in() to authenticated;

-- a new teacher can pick the material when creating a class
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  lcode text := upper(btrim(coalesce(meta->>'leader_code', '')));
  r text := case when meta->>'role' = 'teacher' then 'teacher' else 'student' end;
  mat text := coalesce((select id from public.materials where id = meta->>'material'), 'disciple');
  cid uuid;
begin
  if r = 'teacher' and lcode <> '' then
    select id into cid from public.classes where leader_code = lcode;
    if cid is null then raise exception 'That co-leader code is not right'; end if;
  elsif r = 'teacher' then
    insert into public.classes (name, teacher_id, join_code, material)
    values (coalesce(nullif(btrim(meta->>'class_name'), ''), 'Discipleship Class'), new.id, public.gen_code(), mat)
    returning id into cid;
  else
    select id into cid from public.classes where join_code = upper(btrim(coalesce(meta->>'join_code', '')));
  end if;
  insert into public.profiles (id, name, role, class_id)
  values (new.id, coalesce(nullif(btrim(meta->>'name'), ''), 'Friend'), r, cid);
  insert into public.progress (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
