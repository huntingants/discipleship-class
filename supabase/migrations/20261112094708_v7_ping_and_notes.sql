-- tiny public function a free uptime pinger can call so the project never looks idle
create or replace function public.ping() returns text
language sql stable security invoker set search_path = public as $$ select 'ok'::text $$;
revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;

-- private notes teachers keep about a student (a student here is a profile id or a manual student id)
create table public.student_notes (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null,
  body text not null check (char_length(body) between 1 and 2000),
  follow_up date,
  done boolean not null default false,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index student_notes_class_idx on public.student_notes (class_id);
alter table public.student_notes enable row level security;
create policy student_notes_teachers on public.student_notes for all to authenticated
  using (public.is_teacher() and class_id = public.my_class())
  with check (public.is_teacher() and class_id = public.my_class());
revoke all on public.student_notes from public, anon;
grant select, insert, update, delete on public.student_notes to authenticated;
