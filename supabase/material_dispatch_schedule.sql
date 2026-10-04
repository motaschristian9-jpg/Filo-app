-- Run manually AFTER configuring the function and creating the Vault secret
-- filo_material_worker_secret with the same value as MATERIAL_WORKER_SECRET.
-- No credentials belong in this file. Enable Cron and pg_net in the dashboard.
select cron.schedule(
  'filo-material-delivery',
  '* * * * *',
  $job$
    select net.http_post(
      url := 'https://pvcereixbqctjrxsalhd.supabase.co/functions/v1/material-dispatch',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-worker-secret', (select decrypted_secret from vault.decrypted_secrets
                           where name = 'filo_material_worker_secret' limit 1)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 90000
    )
    where exists (
      select 1 from public.material_dispatch_jobs
      where finished_at is null and available_at <= now() and expires_at > now()
        and (lease_until is null or lease_until < now())
    ) and exists (
      select 1 from vault.decrypted_secrets where name = 'filo_material_worker_secret'
    );
  $job$
);
