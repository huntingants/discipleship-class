-- code generator (shared by join codes and leader codes)
create or replace function public.gen_code() returns text
language plpgsql set search_path = public as $$
declare code text; alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    code := '';
    for i in 1..6 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.classes where join_code = code or leader_code = code);
  end loop;
  return code;
end $$;

alter table public.classes add column leader_code text unique;
update public.classes set leader_code = public.gen_code() where leader_code is null;
alter table public.classes alter column leader_code set not null;
alter table public.classes alter column leader_code set default public.gen_code();

-- sign-up: owner teacher, co-leader (by leader code) or student (by join code)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  lcode text := upper(btrim(coalesce(meta->>'leader_code', '')));
  r text := case when meta->>'role' = 'teacher' then 'teacher' else 'student' end;
  cid uuid;
begin
  if r = 'teacher' and lcode <> '' then
    select id into cid from public.classes where leader_code = lcode;
    if cid is null then raise exception 'That co-leader code is not right'; end if;
  elsif r = 'teacher' then
    insert into public.classes (name, teacher_id, join_code)
    values (coalesce(nullif(btrim(meta->>'class_name'), ''), 'Discipleship Class'), new.id, public.gen_code())
    returning id into cid;
  else
    select id into cid from public.classes where join_code = upper(btrim(coalesce(meta->>'join_code', '')));
  end if;
  insert into public.profiles (id, name, role, class_id)
  values (new.id, coalesce(nullif(btrim(meta->>'name'), ''), 'Friend'), r, cid);
  insert into public.progress (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create or replace function public.check_leader_code(code text) returns text
language sql stable security definer set search_path = public as
$$ select name from public.classes where leader_code = upper(btrim(code)) $$;

-- any leader of the class may edit class settings (not the codes or owner)
drop policy if exists classes_teacher_update on public.classes;
create policy classes_leader_update on public.classes for update to authenticated
  using (id = public.my_class() and public.is_teacher()) with check (id = public.my_class() and public.is_teacher());
revoke update on public.classes from authenticated;
grant update (name, meet, week, ahead, message, message_at) on public.classes to authenticated;

-- new codes
create or replace function public.new_join_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  c := public.gen_code();
  update public.classes set join_code = c where id = public.my_class();
  return c;
end $$;
create or replace function public.new_leader_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  c := public.gen_code();
  update public.classes set leader_code = c where id = public.my_class();
  return c;
end $$;

-- a student with no class joins one by code
create or replace function public.join_class(code text) returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid; cname text;
begin
  if exists (select 1 from public.profiles where id = auth.uid() and role = 'student' and class_id is null) is not true then
    raise exception 'You are already in a class';
  end if;
  select id, name into cid, cname from public.classes where join_code = upper(btrim(code));
  if cid is null then raise exception 'That class code is not right'; end if;
  update public.profiles set class_id = cid where id = auth.uid();
  update public.prayers set class_id = cid where user_id = auth.uid() and class_id is null;
  return cname;
end $$;

-- a leader moves a student into another class using that class's join code
create or replace function public.move_student(sid uuid, code text) returns text
language plpgsql security definer set search_path = public as $$
declare mine uuid; target uuid; tname text;
begin
  select class_id into mine from public.profiles where id = auth.uid() and role = 'teacher';
  if mine is null then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.profiles where id = sid and class_id = mine and role = 'student') then raise exception 'that student is not in your class'; end if;
  select id, name into target, tname from public.classes where join_code = upper(btrim(code));
  if target is null then raise exception 'That class code is not right'; end if;
  update public.profiles set class_id = target where id = sid;
  update public.prayers set class_id = target where user_id = sid and class_id = mine;
  delete from public.attendance where class_id = mine and member_id = sid;
  return tname;
end $$;

-- "I prayed for this"
create table public.prayed (
  prayer_id uuid not null references public.prayers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (prayer_id, user_id)
);
create index on public.prayed (user_id);
alter table public.prayed enable row level security;
create policy prayed_read on public.prayed for select to authenticated
  using (exists (select 1 from public.prayers p where p.id = prayed.prayer_id));
create policy prayed_add on public.prayed for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.prayers p where p.id = prayed.prayer_id));
create policy prayed_remove on public.prayed for delete to authenticated using (user_id = (select auth.uid()));

-- answers written before class
create table public.prep (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson int not null check (lesson between 1 and 63),
  body text not null default '',
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson)
);
alter table public.prep enable row level security;
create policy prep_own on public.prep for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy prep_leader_read on public.prep for select to authenticated
  using (public.is_teacher() and exists (select 1 from public.profiles p where p.id = prep.user_id and p.class_id = public.my_class()));

-- privileges
revoke all on table public.prayed, public.prep from anon;
revoke all on function public.gen_code() from public, anon, authenticated;
revoke all on function public.new_join_code(), public.new_leader_code(), public.join_class(text), public.move_student(uuid, text), public.check_leader_code(text) from public, anon;
grant execute on function public.new_join_code(), public.new_leader_code(), public.join_class(text), public.move_student(uuid, text) to authenticated;
grant execute on function public.check_leader_code(text) to anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
