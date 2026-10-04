create table if not exists public.class_join_limits (
  uid text primary key,
  window_start timestamptz not null,
  attempts integer not null
);
alter table public.class_join_limits enable row level security;
revoke all on public.class_join_limits from anon, authenticated;
grant all on public.class_join_limits to service_role;

create or replace function public.allow_class_join(p_uid text)
returns boolean language sql security definer set search_path = public as $$
  insert into public.class_join_limits as limits values (p_uid, now(), 1)
  on conflict (uid) do update set
    attempts = case when limits.window_start < now() - interval '1 minute'
      then 1 else limits.attempts + 1 end,
    window_start = case when limits.window_start < now() - interval '1 minute'
      then now() else limits.window_start end
  returning attempts <= 10;
$$;
revoke all on function public.allow_class_join(text) from public, anon, authenticated;
grant execute on function public.allow_class_join(text) to service_role;
