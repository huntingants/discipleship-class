-- NOTE: in the live database the admin email below is the real admin address.
-- It is replaced with a placeholder here because this repository is public.
-- Put the admin's email back in before running this file on a new project.

-- Teacher invites table
create table if not exists public.teacher_invites (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default encode(gen_random_bytes(16), 'hex'),
  created_by uuid references auth.users(id) not null,
  used_by uuid references auth.users(id),
  used_at timestamptz,
  created_at timestamptz default now()
);

-- RLS
alter table public.teacher_invites enable row level security;

-- Only the admin can see invites
create policy "Admin can read invites" on public.teacher_invites
  for select using (
    auth.uid() in (select id from auth.users where email = 'ADMIN_EMAIL')
  );

-- Only the admin can insert invites
create policy "Admin can create invites" on public.teacher_invites
  for insert with check (
    auth.uid() in (select id from auth.users where email = 'ADMIN_EMAIL')
  );

-- RPC: create a teacher invite (only admin)
create or replace function public.create_teacher_invite()
returns text
language plpgsql security definer
as $$
declare
  tok text;
begin
  if not exists (select 1 from auth.users where id = auth.uid() and email = 'ADMIN_EMAIL') then
    raise exception 'Only the admin can create teacher invites';
  end if;
  insert into public.teacher_invites (created_by) values (auth.uid()) returning token into tok;
  return tok;
end;
$$;

-- RPC: validate a teacher invite token (public, used during sign-up)
create or replace function public.validate_teacher_invite(token text)
returns boolean
language sql security definer
as $$
  select exists (
    select 1 from public.teacher_invites
    where teacher_invites.token = validate_teacher_invite.token
      and used_by is null
  );
$$;
