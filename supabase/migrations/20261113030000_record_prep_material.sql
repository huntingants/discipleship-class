-- The "Preparatory Lesson" material exists in the live database but was added by hand,
-- not by a migration. This file records it so a new project gets the same rows.
-- Already applied on the live project; safe to run again.
insert into public.materials (id, label, week_offset)
values ('prep', 'Preparatory Lesson', 2000)
on conflict (id) do nothing;
