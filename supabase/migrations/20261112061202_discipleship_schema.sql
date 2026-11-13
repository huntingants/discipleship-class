create table public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Discipleship Class',
  meet text not null default '',
  week int not null default 1 check (week between 1 and 63),
  ahead boolean not null default false,
  message text not null default '',
  message_at timestamptz,
  join_code text not null unique,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default 'student' check (role in ('teacher','student')),
  class_id uuid references public.classes(id) on delete set null,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);

create table public.progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  done int[] not null default '{}',
  verses int[] not null default '{}',
  tasks jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.journal (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson int not null check (lesson between 1 and 63),
  body text not null default '',
  shared boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson)
);

create table public.prayers (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  class_id uuid references public.classes(id) on delete cascade,
  body text not null,
  vis text not null default 't' check (vis in ('t','g')),
  answered boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.manual_students (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.attendance (
  class_id uuid not null references public.classes(id) on delete cascade,
  week int not null check (week between 1 and 63),
  member_id uuid not null,
  primary key (class_id, week, member_id)
);

create index on public.profiles (class_id);
create index on public.prayers (class_id);
create index on public.prayers (user_id);
create index on public.manual_students (class_id);
create index on public.classes (teacher_id);

create or replace function public.my_class() returns uuid
language sql stable security definer set search_path = public as
$$ select class_id from public.profiles where id = auth.uid() $$;

create or replace function public.is_teacher() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher') $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r text := case when meta->>'role' = 'teacher' then 'teacher' else 'student' end;
  cid uuid; code text; alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i int;
begin
  if r = 'teacher' then
    loop
      code := '';
      for i in 1..6 loop code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
      exit when not exists (select 1 from public.classes where join_code = code);
    end loop;
    insert into public.classes (name, teacher_id, join_code)
    values (coalesce(nullif(btrim(meta->>'class_name'), ''), 'Discipleship Class'), new.id, code)
    returning id into cid;
  else
    select id into cid from public.classes where join_code = upper(btrim(coalesce(meta->>'join_code', '')));
  end if;
  insert into public.profiles (id, name, role, class_id)
  values (new.id, coalesce(nullif(btrim(meta->>'name'), ''), 'Friend'), r, cid);
  insert into public.progress (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.check_code(code text) returns text
language sql stable security definer set search_path = public as
$$ select name from public.classes where join_code = upper(btrim(code)) $$;

create or replace function public.class_roster()
returns table (id uuid, name text, joined_at timestamptz, last_seen timestamptz, done int[], verses int[], tasks jsonb, journal_lessons int[])
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.joined_at, p.last_seen,
         coalesce(g.done, '{}'), coalesce(g.verses, '{}'), coalesce(g.tasks, '{}'::jsonb),
         coalesce((select array_agg(j.lesson order by j.lesson) from public.journal j where j.user_id = p.id and btrim(j.body) <> ''), '{}')
  from public.profiles p
  left join public.progress g on g.user_id = p.id
  where p.role = 'student'
    and p.class_id = (select t.class_id from public.profiles t where t.id = auth.uid() and t.role = 'teacher')
$$;

alter table public.classes enable row level security;
alter table public.profiles enable row level security;
alter table public.progress enable row level security;
alter table public.journal enable row level security;
alter table public.prayers enable row level security;
alter table public.manual_students enable row level security;
alter table public.attendance enable row level security;

create policy classes_read on public.classes for select to authenticated using (id = public.my_class());
create policy classes_teacher_update on public.classes for update to authenticated
  using (teacher_id = (select auth.uid())) with check (teacher_id = (select auth.uid()));

create policy profiles_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or class_id = public.my_class());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy progress_own on public.progress for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy journal_own on public.journal for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy journal_teacher_shared on public.journal for select to authenticated
  using (shared and public.is_teacher() and exists (
    select 1 from public.profiles p where p.id = journal.user_id and p.class_id = public.my_class()));

create policy prayers_own on public.prayers for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and class_id is not distinct from public.my_class());
create policy prayers_class_read on public.prayers for select to authenticated
  using (class_id = public.my_class() and (vis = 'g' or public.is_teacher()));
create policy prayers_teacher_remove on public.prayers for delete to authenticated
  using (class_id = public.my_class() and public.is_teacher() and vis = 'g');

create policy manual_teacher on public.manual_students for all to authenticated
  using (public.is_teacher() and class_id = public.my_class())
  with check (public.is_teacher() and class_id = public.my_class());
create policy attendance_teacher on public.attendance for all to authenticated
  using (public.is_teacher() and class_id = public.my_class())
  with check (public.is_teacher() and class_id = public.my_class());

revoke all on all tables in schema public from anon;
revoke update on public.profiles from authenticated;
grant update (name, last_seen) on public.profiles to authenticated;
revoke insert, delete on public.profiles from authenticated;
revoke insert, delete on public.classes from authenticated;
revoke all on function public.my_class(), public.is_teacher(), public.class_roster(), public.handle_new_user() from public, anon;
grant execute on function public.my_class(), public.is_teacher(), public.class_roster() to authenticated;
grant execute on function public.check_code(text) to anon, authenticated;
