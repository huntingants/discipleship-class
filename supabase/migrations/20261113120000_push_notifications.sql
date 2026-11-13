-- Push notifications: students' phones register here; the "notify" Edge Function sends to them.

-- one row per phone/browser that turned notifications on
create table public.push_subs (
  endpoint text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index push_subs_user_idx on public.push_subs (user_id);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from public, anon, authenticated;

-- save or remove this phone's subscription for the signed-in person
-- (a function, so a shared phone moves to whoever is signed in now)
create or replace function public.save_push_sub(p_endpoint text, p_key text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if length(p_endpoint) > 1000 or p_endpoint !~ '^https://' then raise exception 'bad endpoint'; end if;
  if length(p_key) > 200 or length(p_auth) > 100 then raise exception 'bad keys'; end if;
  insert into public.push_subs as s (endpoint, user_id, p256dh, auth)
  values (p_endpoint, auth.uid(), p_key, p_auth)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
end $$;
create or replace function public.remove_push_sub(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_subs where endpoint = p_endpoint and user_id = auth.uid()
$$;
revoke all on function public.save_push_sub(text, text, text), public.remove_push_sub(text) from public, anon;
grant execute on function public.save_push_sub(text, text, text), public.remove_push_sub(text) to authenticated;

-- what was sent, so the same notice is not sent again within a minute
create table public.push_log (
  id bigint generated always as identity primary key,
  class_id uuid not null references public.classes(id) on delete cascade,
  kind text not null,
  sent_by uuid,
  recipients int not null default 0,
  sent_at timestamptz not null default now()
);
create index push_log_class_idx on public.push_log (class_id, kind, sent_at desc);
alter table public.push_log enable row level security;
revoke all on public.push_log from public, anon, authenticated;

-- server-only settings (the push signing keys). No policies and no grants: only the service role can read it.
create table if not exists public.app_secrets (
  name text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from public, anon, authenticated;
-- The VAPID keys are added separately and are not stored in this repository:
--   insert into public.app_secrets (name, value) values ('vapid_public', '...'), ('vapid_private', '...'), ('vapid_subject', 'https://...');
