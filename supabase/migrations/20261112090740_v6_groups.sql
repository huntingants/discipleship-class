-- A teacher can lead several groups (up to 10). profiles.class_id stays the ACTIVE group, so every existing policy keeps working.
create table public.teacher_classes (
  teacher_id uuid not null references auth.users(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (teacher_id, class_id)
);
alter table public.teacher_classes enable row level security;
create policy teacher_classes_own on public.teacher_classes for select to authenticated using (teacher_id = (select auth.uid()));
revoke all on public.teacher_classes from public, anon;
grant select on public.teacher_classes to authenticated;

insert into public.teacher_classes (teacher_id, class_id)
select p.id, p.class_id from public.profiles p where p.role = 'teacher' and p.class_id is not null
on conflict do nothing;

create or replace function public.my_groups() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
    'id', c.id, 'name', c.name, 'material', c.material, 'week', c.week,
    'owner', c.teacher_id = auth.uid(),
    'students', (select count(*) from public.profiles s where s.class_id = c.id and s.role = 'student'),
    'active', c.id = (select class_id from public.profiles where id = auth.uid())
  ) order by tc.created_at, c.name), '[]'::json)
  from public.teacher_classes tc join public.classes c on c.id = tc.class_id
  where tc.teacher_id = auth.uid() and public.is_teacher()
$$;

create or replace function public.switch_class(cid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.teacher_classes where teacher_id = auth.uid() and class_id = cid) then
    raise exception 'That group is not yours';
  end if;
  update public.profiles set class_id = cid where id = auth.uid();
end $$;

create or replace function public.create_class(cname text, mat text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; n int;
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  select count(*) into n from public.teacher_classes where teacher_id = auth.uid();
  if n >= 10 then raise exception 'You can lead up to 10 groups'; end if;
  insert into public.classes (name, teacher_id, join_code, material)
  values (coalesce(nullif(btrim(cname), ''), 'Discipleship Class'), auth.uid(), public.gen_code(),
          coalesce((select id from public.materials where id = mat), 'disciple'))
  returning id into cid;
  insert into public.teacher_classes (teacher_id, class_id) values (auth.uid(), cid);
  update public.profiles set class_id = cid where id = auth.uid();
  return cid;
end $$;

-- only the group's creator can delete it; students stay in the app without a class; every leader is moved to another of their groups
create or replace function public.delete_class(cid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if not public.is_teacher() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.classes where id = cid and teacher_id = auth.uid()) then
    raise exception 'Only the person who made this group can delete it';
  end if;
  if (select count(*) from public.teacher_classes where teacher_id = auth.uid()) < 2 then
    raise exception 'You need at least one other group before you can delete this one';
  end if;
  update public.prayers set class_id = null where class_id = cid;
  for t in select teacher_id from public.teacher_classes where class_id = cid loop
    update public.profiles set class_id = (select tc.class_id from public.teacher_classes tc where tc.teacher_id = t and tc.class_id <> cid order by tc.created_at limit 1)
    where id = t and class_id = cid;
  end loop;
  delete from public.classes where id = cid;
end $$;

revoke all on function public.my_groups() from public, anon;
revoke all on function public.switch_class(uuid) from public, anon;
revoke all on function public.create_class(text, text) from public, anon;
revoke all on function public.delete_class(uuid) from public, anon;
grant execute on function public.my_groups() to authenticated;
grant execute on function public.switch_class(uuid) to authenticated;
grant execute on function public.create_class(text, text) to authenticated;
grant execute on function public.delete_class(uuid) to authenticated;

-- new teachers and new co-leaders get a membership row
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
  if r = 'teacher' and cid is not null then
    insert into public.teacher_classes (teacher_id, class_id) values (new.id, cid) on conflict do nothing;
  end if;
  insert into public.progress (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
