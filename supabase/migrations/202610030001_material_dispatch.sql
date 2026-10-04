-- Only Edge Functions may access the delivery queue. Clients use Firebase Auth.
create table if not exists public.material_dispatch_jobs (
  class_id text not null,
  material_id text not null,
  author_id text not null,
  enrollment_page text not null default '',
  device_page text not null default '',
  available_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 day',
  lease_id uuid,
  lease_until timestamptz,
  finished_at timestamptz,
  attempts integer not null default 0,
  primary key (class_id, material_id)
);
alter table public.material_dispatch_jobs enable row level security;
revoke all on public.material_dispatch_jobs from anon, authenticated;
grant all on public.material_dispatch_jobs to service_role;

create or replace function public.prepare_material_dispatch(p_class text, p_material text, p_author text)
returns void language sql security definer set search_path = '' as $$
  insert into public.material_dispatch_jobs(class_id, material_id, author_id)
  values (p_class, p_material, p_author)
  on conflict (class_id, material_id) do update
  set available_at = now(), expires_at = now() + interval '1 day'
  where public.material_dispatch_jobs.author_id = excluded.author_id
    and public.material_dispatch_jobs.finished_at is null;
$$;

create or replace function public.claim_material_dispatch(p_class text default null, p_material text default null)
returns setof public.material_dispatch_jobs
language sql security definer set search_path = '' as $$
  update public.material_dispatch_jobs j
  set lease_id = gen_random_uuid(), lease_until = now() + interval '3 minutes',
      attempts = attempts + 1
  where (j.class_id, j.material_id) = (
    select class_id, material_id from public.material_dispatch_jobs
    where finished_at is null and available_at <= now() and expires_at > now()
      and (lease_until is null or lease_until < now())
      and (p_class is null or class_id = p_class)
      and (p_material is null or material_id = p_material)
    order by available_at for update skip locked limit 1
  ) returning j.*;
$$;
revoke all on function public.prepare_material_dispatch(text, text, text) from public, anon, authenticated;
revoke all on function public.claim_material_dispatch(text, text) from public, anon, authenticated;
grant execute on function public.prepare_material_dispatch(text, text, text) to service_role;
grant execute on function public.claim_material_dispatch(text, text) to service_role;
