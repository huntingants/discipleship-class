create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  lcode text := upper(btrim(coalesce(meta->>'leader_code', '')));
  r text := case when meta->>'role' = 'teacher' then 'teacher' else 'student' end;
  mat text := coalesce((select id from public.materials where id = meta->>'material'), 'disciple');
  inv_token text := btrim(coalesce(meta->>'invite_token', ''));
  cid uuid;
begin
  -- Guard: teacher/leader sign-ups require a valid invite token
  if r = 'teacher' and inv_token = '' then
    raise exception 'Teacher accounts require an invitation';
  end if;
  if r = 'teacher' and inv_token <> '' then
    if not exists (select 1 from public.teacher_invites where token = inv_token and used_by is null) then
      raise exception 'Invalid or already used invite token';
    end if;
    -- Mark the token as used
    update public.teacher_invites set used_by = new.id, used_at = now() where token = inv_token and used_by is null;
  end if;

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
end;
$$;
