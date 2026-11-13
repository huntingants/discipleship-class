create or replace function public.remove_student(sid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select class_id into cid from public.profiles where id = auth.uid() and role = 'teacher';
  if cid is null then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.profiles where id = sid and class_id = cid and role = 'student') then
    raise exception 'that student is not in your class';
  end if;
  update public.profiles set class_id = null where id = sid;
  update public.prayers set class_id = null where user_id = sid and class_id = cid;
  delete from public.attendance where class_id = cid and member_id = sid;
end $$;
revoke all on function public.remove_student(uuid) from public, anon;
grant execute on function public.remove_student(uuid) to authenticated;
