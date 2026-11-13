alter table public.classes add column checkin_at timestamptz;
grant select (checkin_at) on public.classes to authenticated;

-- opening check-in stamps the time; moving to another lesson closes it
create or replace function public.classes_checkin_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.checkin_open and not coalesce(old.checkin_open, false) then
    new.checkin_at := now();
  end if;
  if new.week is distinct from old.week then
    new.checkin_open := false;
  end if;
  return new;
end $$;

drop trigger if exists classes_checkin_guard on public.classes;
create trigger classes_checkin_guard before update on public.classes
  for each row execute function public.classes_checkin_guard();
revoke all on function public.classes_checkin_guard() from public, anon, authenticated;

-- check-in also stops by itself four hours after it was opened
create or replace function public.check_in() returns int
language plpgsql security definer set search_path = public as $$
declare cid uuid; wk int; open_ boolean; at_ timestamptz;
begin
  select c.id, c.week, c.checkin_open, c.checkin_at into cid, wk, open_, at_
  from public.classes c join public.profiles p on p.class_id = c.id
  where p.id = auth.uid() and p.role = 'student';
  if cid is null then raise exception 'You are not in a class'; end if;
  if not open_ or (at_ is not null and at_ < now() - interval '4 hours') then
    raise exception 'Check-in is not open yet';
  end if;
  insert into public.attendance (class_id, week, member_id) values (cid, wk, auth.uid()) on conflict do nothing;
  return wk;
end $$;
revoke all on function public.check_in() from public, anon;
grant execute on function public.check_in() to authenticated;
