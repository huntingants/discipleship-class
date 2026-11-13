-- Live updates: the app listens for changes to these tables instead of asking every few seconds.
-- Realtime applies each table's row level security, so people only hear about rows they could already read.
alter publication supabase_realtime add table
  public.classes, public.profiles, public.prayers, public.prayed, public.attendance,
  public.journal, public.prep, public.manual_students, public.student_notes;
