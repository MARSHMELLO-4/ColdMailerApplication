create extension if not exists pgcrypto;

create table if not exists public.resumes (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  storage_path text not null unique,
  content_type text not null default 'application/octet-stream',
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  is_active boolean not null default true,
  uploaded_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  normalized_email text not null unique,
  first_contacted_at timestamptz,
  last_contacted_at timestamptz,
  last_attempted_at timestamptz not null default timezone('utc', now()),
  total_sent integer not null default 0 check (total_sent >= 0),
  last_subject text,
  last_status text not null default 'sent',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint contacts_email_format check (
    email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  ),
  constraint contacts_status_check check (last_status in ('sent', 'failed'))
);

create table if not exists public.outbound_emails (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.contacts(id) on delete set null,
  recipient_email text not null,
  subject text not null,
  body text not null,
  resume_storage_path text,
  status text not null check (status in ('sent', 'failed')),
  provider_message_id text,
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists contacts_last_attempted_idx
  on public.contacts (last_attempted_at desc);

create index if not exists outbound_emails_created_at_idx
  on public.outbound_emails (created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists contacts_set_updated_at on public.contacts;
create trigger contacts_set_updated_at
before update on public.contacts
for each row
execute function public.set_updated_at();

create or replace function public.record_email_delivery(
  p_recipient_email text,
  p_subject text,
  p_body text,
  p_resume_storage_path text,
  p_status text,
  p_provider_message_id text default null,
  p_error_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact_id uuid;
  v_normalized_email text := lower(trim(p_recipient_email));
  v_now timestamptz := timezone('utc', now());
begin
  if p_status not in ('sent', 'failed') then
    raise exception 'Invalid status: %', p_status;
  end if;

  insert into public.contacts (
    email,
    normalized_email,
    first_contacted_at,
    last_contacted_at,
    last_attempted_at,
    total_sent,
    last_subject,
    last_status
  )
  values (
    trim(p_recipient_email),
    v_normalized_email,
    case when p_status = 'sent' then v_now else null end,
    case when p_status = 'sent' then v_now else null end,
    v_now,
    case when p_status = 'sent' then 1 else 0 end,
    p_subject,
    p_status
  )
  on conflict (normalized_email)
  do update set
    email = excluded.email,
    first_contacted_at = coalesce(
      public.contacts.first_contacted_at,
      case when p_status = 'sent' then v_now else null end
    ),
    last_contacted_at = case
      when p_status = 'sent' then v_now
      else public.contacts.last_contacted_at
    end,
    last_attempted_at = v_now,
    total_sent = public.contacts.total_sent + case when p_status = 'sent' then 1 else 0 end,
    last_subject = p_subject,
    last_status = p_status
  returning id into v_contact_id;

  insert into public.outbound_emails (
    contact_id,
    recipient_email,
    subject,
    body,
    resume_storage_path,
    status,
    provider_message_id,
    error_message,
    sent_at
  )
  values (
    v_contact_id,
    trim(p_recipient_email),
    p_subject,
    p_body,
    p_resume_storage_path,
    p_status,
    p_provider_message_id,
    p_error_message,
    case when p_status = 'sent' then v_now else null end
  );

  return v_contact_id;
end;
$$;

grant execute on function public.record_email_delivery(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to service_role;

alter table public.resumes enable row level security;
alter table public.contacts enable row level security;
alter table public.outbound_emails enable row level security;

drop policy if exists "Allow anonymous resume reads" on public.resumes;
create policy "Allow anonymous resume reads"
on public.resumes
for select
to anon
using (true);

drop policy if exists "Allow anonymous resume inserts" on public.resumes;
create policy "Allow anonymous resume inserts"
on public.resumes
for insert
to anon
with check (true);

drop policy if exists "Allow anonymous contact reads" on public.contacts;
create policy "Allow anonymous contact reads"
on public.contacts
for select
to anon
using (true);

drop policy if exists "Allow anonymous outbound email reads" on public.outbound_emails;
create policy "Allow anonymous outbound email reads"
on public.outbound_emails
for select
to anon
using (true);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'resume_uploads',
  'resume_uploads',
  false,
  10485760,
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Allow anonymous resume object reads" on storage.objects;
create policy "Allow anonymous resume object reads"
on storage.objects
for select
to anon
using (bucket_id = 'resume_uploads');

drop policy if exists "Allow anonymous resume object uploads" on storage.objects;
create policy "Allow anonymous resume object uploads"
on storage.objects
for insert
to anon
with check (bucket_id = 'resume_uploads');

drop policy if exists "Allow anonymous resume object updates" on storage.objects;
create policy "Allow anonymous resume object updates"
on storage.objects
for update
to anon
using (bucket_id = 'resume_uploads')
with check (bucket_id = 'resume_uploads');
