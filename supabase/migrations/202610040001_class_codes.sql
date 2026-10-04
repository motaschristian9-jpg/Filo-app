create table if not exists public.class_codes (
  class_id text primary key,
  code text not null unique check (code ~ '^[A-HJ-KM-NP-Z2-9]{6}$')
);
alter table public.class_codes enable row level security;
revoke all on public.class_codes from anon, authenticated;
grant all on public.class_codes to service_role;
