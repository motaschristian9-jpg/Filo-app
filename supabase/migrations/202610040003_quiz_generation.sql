create table if not exists public.quiz_generation_limits (
  uid text primary key, day date not null, attempts integer not null
);
alter table public.quiz_generation_limits enable row level security;
revoke all on public.quiz_generation_limits from anon, authenticated;
grant all on public.quiz_generation_limits to service_role;
create or replace function public.allow_quiz_generation(p_uid text)
returns boolean language sql security definer set search_path = public as $$
  insert into public.quiz_generation_limits as limits values (p_uid, current_date, 1)
  on conflict (uid) do update set
    attempts = case when limits.day <> current_date then 1 else limits.attempts + 1 end,
    day = current_date returning attempts <= 10;
$$;
revoke all on function public.allow_quiz_generation(text) from public, anon, authenticated;
grant execute on function public.allow_quiz_generation(text) to service_role;
