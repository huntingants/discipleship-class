revoke select on public.classes from authenticated;
grant select (id, name, meet, week, ahead, message, message_at, join_code, teacher_id, created_at) on public.classes to authenticated;

create or replace function public.get_leader_code() returns text
language sql stable security definer set search_path = public as
$$ select c.leader_code from public.classes c where c.id = public.my_class() and public.is_teacher() $$;
revoke all on function public.get_leader_code() from public, anon;
grant execute on function public.get_leader_code() to authenticated;
