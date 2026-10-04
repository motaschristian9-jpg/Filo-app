-- Private lesson text only; no client reads/writes or assessment-answer caching.
begin;
create table if not exists public.quiz_lesson_cache (
  cache_key text primary key check (cache_key ~ '^[a-f0-9]{64}$'),
  owner_uid text not null,
  class_id text not null,
  lesson_text text not null check (char_length(lesson_text) between 1 and 200000),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days'
);
alter table public.quiz_lesson_cache enable row level security;
revoke all on public.quiz_lesson_cache from anon, authenticated;
grant all on public.quiz_lesson_cache to service_role;
create index if not exists quiz_lesson_cache_owner_created
  on public.quiz_lesson_cache(owner_uid, created_at);
create index if not exists quiz_lesson_cache_expiry on public.quiz_lesson_cache(expires_at);

create or replace function public.store_quiz_lesson_text(
  p_key text, p_uid text, p_class text, p_text text
) returns void language plpgsql security definer set search_path = public as $$
begin
  -- Serialize same-owner cache writes so concurrent generations respect the cap.
  perform pg_advisory_xact_lock(hashtextextended(p_uid, 0));
  delete from public.quiz_lesson_cache where expires_at <= now();
  insert into public.quiz_lesson_cache(cache_key, owner_uid, class_id, lesson_text)
    values (p_key, p_uid, p_class, p_text)
    on conflict (cache_key) do update set lesson_text = excluded.lesson_text,
      created_at = now(), expires_at = now() + interval '7 days';
  delete from public.quiz_lesson_cache where cache_key in (
    select cache_key from public.quiz_lesson_cache where owner_uid = p_uid
      order by created_at desc, cache_key offset 30
  );
end;
$$;
revoke all on function public.store_quiz_lesson_text(text,text,text,text) from public, anon, authenticated;
grant execute on function public.store_quiz_lesson_text(text,text,text,text) to service_role;
commit;
