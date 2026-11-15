-- App error log: when the app crashes on someone's device it records a short note here.
-- Nobody can read or change the table directly. The app writes through log_client_error(),
-- and only the app admin can read through recent_client_errors().
create table public.client_errors (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  who text not null,
  user_id uuid,
  msg text not null,
  src text,
  page text,
  agent text,
  ver text
);
create index client_errors_at_idx on public.client_errors (at desc);
create index client_errors_who_idx on public.client_errors (who, at);
alter table public.client_errors enable row level security;
revoke all on public.client_errors from public, anon, authenticated;

create or replace function public.log_client_error(p_msg text, p_src text default null, p_page text default null, p_agent text default null, p_ver text default null)
returns void language plpgsql security definer set search_path = public as $$
declare hdr json; v_who text; n int;
begin
  if coalesce(btrim(p_msg), '') = '' then return; end if;
  begin hdr := nullif(current_setting('request.headers', true), '')::json; exception when others then hdr := null; end;
  v_who := coalesce(auth.uid()::text,
    nullif(btrim(split_part(coalesce(hdr->>'cf-connecting-ip', hdr->>'x-real-ip', hdr->>'x-forwarded-for', ''), ',', 1)), ''),
    'unknown');
  -- at most 20 reports an hour from one person or address, and 5000 in the whole table
  select count(*) into n from public.client_errors where who = v_who and at > now() - interval '1 hour';
  if n >= 20 then return; end if;
  delete from public.client_errors where at < now() - interval '30 days';
  select count(*) into n from public.client_errors;
  if n >= 5000 then return; end if;
  insert into public.client_errors (who, user_id, msg, src, page, agent, ver)
  values (v_who, auth.uid(), left(p_msg, 500), left(p_src, 300), left(p_page, 200), left(p_agent, 200), left(p_ver, 40));
end $$;
revoke all on function public.log_client_error(text, text, text, text, text) from public;
grant execute on function public.log_client_error(text, text, text, text, text) to anon, authenticated;

create or replace function public.recent_client_errors()
returns table (at timestamptz, msg text, src text, page text, agent text, ver text, signed_in boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'Only the app admin can see this.'; end if;
  return query select e.at, e.msg, e.src, e.page, e.agent, e.ver, e.user_id is not null
    from public.client_errors e order by e.at desc limit 50;
end $$;
revoke all on function public.recent_client_errors() from public, anon;
grant execute on function public.recent_client_errors() to authenticated;
