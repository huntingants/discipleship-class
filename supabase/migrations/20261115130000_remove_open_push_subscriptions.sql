-- Remove the push_subscriptions table added outside this repo on 2026-11-15.
-- Its rules let anyone on the internet read, add or delete every phone's notification
-- sign-up, and it was used by the "send-push" function, which needed no sign-in.
-- Class notifications use push_subs and the "notify" function (teachers only).
-- The table was empty when it was removed.
do $$ begin
  if (select count(*) from public.push_subscriptions) > 0 then
    raise exception 'push_subscriptions is not empty; not dropping';
  end if;
end $$;
drop table public.push_subscriptions;
