-- Private by default. No anonymous/authenticated object policies are added:
-- signed grants come only from the Firebase-authorized Edge Function.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('class-materials', 'class-materials', false, 26214400,
        array['application/octet-stream'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
