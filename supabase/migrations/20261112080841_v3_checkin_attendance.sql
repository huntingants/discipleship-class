alter table public.classes add column checkin_open boolean not null default false;
grant select (checkin_open) on public.classes to authenticated;
grant update (checkin_open) on public.classes to authenticated;

-- a student marks themselves present for the class's current week, only while check-in is open
create or replace function public.check_in() returns int
language plpgsql security definer set search_path = public as $$
declare cid uuid; wk int; open_ boolean;
begin
  select c.id, c.week, c.checkin_open into cid, wk, open_
  from public.classes c join public.profiles p on p.class_id = c.id
  where p.id = auth.uid() and p.role = 'student';
  if cid is null then raise exception 'You are not in a class'; end if;
  if not open_ then raise exception 'Check-in is not open yet'; end if;
  insert into public.attendance (class_id, week, member_id) values (cid, wk, auth.uid()) on conflict do nothing;
  return wk;
end $$;

-- a student's own attendance: the weeks they attended and the weeks the class has met
create or replace function public.my_attendance() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'mine', coalesce((select array_agg(a.week order by a.week) from public.attendance a where a.member_id = auth.uid() and a.class_id = public.my_class()), '{}'),
    'held', coalesce((select array_agg(distinct a.week order by a.week) from public.attendance a where a.class_id = public.my_class()), '{}'))
$$;

revoke all on function public.check_in(), public.my_attendance() from public, anon;
grant execute on function public.check_in(), public.my_attendance() to authenticated;
