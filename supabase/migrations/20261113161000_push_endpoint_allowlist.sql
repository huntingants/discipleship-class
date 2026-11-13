-- Only accept push addresses from the real browser push services (Google, Mozilla, Microsoft, Apple),
-- so the notify function never sends requests anywhere else.
create or replace function public.save_push_sub(p_endpoint text, p_key text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if length(p_endpoint) > 1000
     or p_endpoint !~* '^https://([a-z0-9-]+\.)*(fcm\.googleapis\.com|push\.services\.mozilla\.com|notify\.windows\.com|push\.apple\.com)(/|$)'
  then raise exception 'bad endpoint'; end if;
  if length(p_key) > 200 or length(p_auth) > 100 then raise exception 'bad keys'; end if;
  insert into public.push_subs as s (endpoint, user_id, p256dh, auth)
  values (p_endpoint, auth.uid(), p_key, p_auth)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
end $$;
