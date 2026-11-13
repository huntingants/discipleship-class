-- Security hardening (2026-11-13 review)

-- 1. Limit code guessing. Checking a class code or co-leader code is allowed 15 times per 10 minutes
--    and 60 times per day for each signed-in person, or each internet address when signed out.
create table public.code_attempts (
  id bigint generated always as identity primary key,
  who text not null,
  at timestamptz not null default now()
);
create index code_attempts_who_idx on public.code_attempts (who, at);
alter table public.code_attempts enable row level security;
revoke all on public.code_attempts from public, anon, authenticated;

create or replace function public.code_guard() returns void
language plpgsql security definer set search_path = public as $$
declare hdr json; v_who text; n10 int; nday int;
begin
  begin hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then hdr := null; end;
  v_who := coalesce(auth.uid()::text,
    nullif(btrim(split_part(coalesce(hdr->>'cf-connecting-ip', hdr->>'x-real-ip', hdr->>'x-forwarded-for', ''), ',', 1)), ''),
    'unknown');
  delete from public.code_attempts where at < now() - interval '1 day';
  select count(*) filter (where at > now() - interval '10 minutes'), count(*) into n10, nday
    from public.code_attempts where who = v_who;
  if n10 >= 15 or nday >= 60 then
    raise exception 'Too many tries. Please wait a few minutes and try again.';
  end if;
  insert into public.code_attempts (who) values (v_who);
end $$;
revoke all on function public.code_guard() from public, anon, authenticated;

create or replace function public.check_code(code text) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform public.code_guard();
  return (select name from public.classes where join_code = upper(btrim(code)));
end $$;
create or replace function public.check_leader_code(code text) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform public.code_guard();
  return (select name from public.classes where leader_code = upper(btrim(code)));
end $$;

create or replace function public.join_class(code text) returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid; cname text;
begin
  if exists (select 1 from public.profiles where id = auth.uid() and role = 'student' and class_id is null) is not true then
    raise exception 'You are already in a class';
  end if;
  perform public.code_guard();
  select id, name into cid, cname from public.classes where join_code = upper(btrim(code));
  if cid is null then raise exception 'That class code is not right'; end if;
  update public.profiles set class_id = cid where id = auth.uid();
  update public.prayers set class_id = cid where user_id = auth.uid() and class_id is null;
  return cname;
end $$;

create or replace function public.move_student(sid uuid, code text) returns text
language plpgsql security definer set search_path = public as $$
declare mine uuid; target uuid; tname text;
begin
  select class_id into mine from public.profiles where id = auth.uid() and role = 'teacher';
  if mine is null then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.profiles where id = sid and class_id = mine and role = 'student') then raise exception 'that student is not in your class'; end if;
  perform public.code_guard();
  select id, name into target, tname from public.classes where join_code = upper(btrim(code));
  if target is null then raise exception 'That class code is not right'; end if;
  update public.profiles set class_id = target where id = sid;
  update public.prayers set class_id = target where user_id = sid and class_id = mine;
  delete from public.attendance where class_id = mine and member_id = sid;
  return tname;
end $$;

-- 2. Co-leader codes give leader access, so make them 10 characters (about 800 trillion possibilities).
create or replace function public.gen_leader_code() returns text
language plpgsql set search_path = public as $$
declare code text; alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    code := '';
    for i in 1..10 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from public.classes where join_code = code or leader_code = code);
  end loop;
  return code;
end $$;
revoke all on function public.gen_leader_code() from public, anon, authenticated;
alter table public.classes alter column leader_code set default public.gen_leader_code();
create or replace function public.new_leader_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  c := public.gen_leader_code();
  update public.classes set leader_code = c where id = public.my_class();
  return c;
end $$;
-- replace existing short co-leader codes
update public.classes set leader_code = public.gen_leader_code() where length(leader_code) < 10;

-- 3. Size limits, so nobody can fill the database or break other people's screens with huge text.
alter table public.profiles add constraint profiles_name_len check (char_length(name) <= 60);
alter table public.manual_students add constraint manual_students_name_len check (char_length(name) <= 60);
alter table public.classes add constraint classes_text_len check (char_length(name) <= 80 and char_length(meet) <= 200 and char_length(message) <= 2000);
alter table public.prayers add constraint prayers_body_len check (char_length(body) <= 2000);
alter table public.journal add constraint journal_body_len check (char_length(body) <= 20000);
alter table public.prep add constraint prep_body_len check (char_length(body) <= 10000);
alter table public.progress add constraint progress_size check (
  cardinality(done) <= 5000 and cardinality(verses) <= 5000 and pg_column_size(tasks) <= 200000);

-- 4. Let "test" notifications be rate limited per person too (they have no class).
alter table public.push_log alter column class_id drop not null;
create index push_log_sender_idx on public.push_log (sent_by, kind, sent_at desc);

-- 5. Indexes the database advisor asked for.
create index if not exists classes_material_idx on public.classes (material);
create index if not exists teacher_classes_class_idx on public.teacher_classes (class_id);
create index if not exists teacher_invites_created_by_idx on public.teacher_invites (created_by);
create index if not exists teacher_invites_used_by_idx on public.teacher_invites (used_by);
