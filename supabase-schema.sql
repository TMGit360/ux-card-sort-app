create extension if not exists pgcrypto;

-- Clean up old views that may conflict with renamed columns or prior schemas
DROP VIEW IF EXISTS public.participant_submissions CASCADE;
DROP VIEW IF EXISTS public.participant_submissions_admin CASCADE;
DROP VIEW IF EXISTS public.study_admin_directory CASCADE;
DROP VIEW IF EXISTS public.admin_studies CASCADE;

-- Clean up old policies so this script can be re-run safely
DROP POLICY IF EXISTS "admins view their profile" ON public.admin_profiles;
DROP POLICY IF EXISTS "admins upsert their profile" ON public.admin_profiles;
DROP POLICY IF EXISTS "admins update their profile" ON public.admin_profiles;
DROP POLICY IF EXISTS "study admins view studies" ON public.studies;
DROP POLICY IF EXISTS "study admins view study_admins" ON public.study_admins;
DROP POLICY IF EXISTS "study admins view templates" ON public.sort_templates;
DROP POLICY IF EXISTS "study admins insert templates" ON public.sort_templates;
DROP POLICY IF EXISTS "study admins update templates" ON public.sort_templates;
DROP POLICY IF EXISTS "study admins view participants" ON public.participants;
DROP POLICY IF EXISTS "study admins view submissions" ON public.submissions;

create table if not exists public.admin_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.studies (
  id uuid primary key default gen_random_uuid(),
  study_id text not null unique,
  study_name text not null,
  study_key text not null,
  public_token text not null unique default encode(gen_random_bytes(18), 'hex'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.study_admins (
  study_id uuid not null references public.studies(id) on delete cascade,
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (study_id, admin_user_id)
);

create table if not exists public.sort_templates (
  id uuid primary key default gen_random_uuid(),
  study_id uuid not null references public.studies(id) on delete cascade,
  template_name text not null default 'Default template',
  cards jsonb not null default '[]'::jsonb,
  categories jsonb not null default '[]'::jsonb,
  allow_category_editing boolean not null default true,
  is_randomized boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  user_id text not null unique default ('user_' || replace(gen_random_uuid()::text, '-', '')),
  study_id uuid not null references public.studies(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  study_id uuid not null references public.studies(id) on delete cascade,
  participant_id uuid not null references public.participants(id) on delete cascade,
  template_id uuid not null references public.sort_templates(id) on delete restrict,
  result_json jsonb not null,
  submitted_at timestamptz not null default now()
);

create index if not exists idx_study_admins_admin_user_id on public.study_admins(admin_user_id);
create index if not exists idx_sort_templates_study_id on public.sort_templates(study_id);
create index if not exists idx_participants_study_id on public.participants(study_id);
create index if not exists idx_submissions_study_id on public.submissions(study_id);
create index if not exists idx_submissions_participant_id on public.submissions(participant_id);

create or replace function public.is_study_admin(p_study_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_admins sa
    where sa.study_id = p_study_uuid
      and sa.admin_user_id = auth.uid()
  );
$$;

create or replace function public.get_public_study_context(p_public_token text)
returns table (
  study_uuid uuid,
  study_id text,
  study_name text,
  public_token text
)
language sql
security definer
set search_path = public
as $$
  select s.id, s.study_id, s.study_name, s.public_token
  from public.studies s
  where s.public_token = p_public_token;
$$;

create or replace function public.create_study_with_template(
  p_study_id text,
  p_study_name text,
  p_study_key text,
  p_template_name text,
  p_cards jsonb,
  p_categories jsonb,
  p_allow_category_editing boolean,
  p_is_randomized boolean
)
returns table (
  study_uuid uuid,
  study_id text,
  public_token text,
  template_uuid uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_study public.studies;
  v_template public.sort_templates;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  insert into public.admin_profiles (user_id, email)
  values (auth.uid(), coalesce(auth.jwt() ->> 'email', ''))
  on conflict (user_id) do update set email = excluded.email;

  insert into public.studies (study_id, study_name, study_key, created_by)
  values (p_study_id, p_study_name, p_study_key, auth.uid())
  returning * into v_study;

  insert into public.study_admins (study_id, admin_user_id)
  values (v_study.id, auth.uid())
  on conflict do nothing;

  insert into public.sort_templates (
    study_id,
    template_name,
    cards,
    categories,
    allow_category_editing,
    is_randomized,
    is_active,
    created_by
  ) values (
    v_study.id,
    coalesce(nullif(trim(p_template_name), ''), 'Default template'),
    coalesce(p_cards, '[]'::jsonb),
    coalesce(p_categories, '[]'::jsonb),
    coalesce(p_allow_category_editing, true),
    coalesce(p_is_randomized, false),
    true,
    auth.uid()
  ) returning * into v_template;

  return query
  select v_study.id, v_study.study_id, v_study.public_token, v_template.id;
end;
$$;

create or replace function public.link_admin_to_study(
  p_study_id text,
  p_study_key text
)
returns table (
  study_uuid uuid,
  study_id text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_study public.studies;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select * into v_study
  from public.studies
  where studies.study_id = p_study_id
    and studies.study_key = p_study_key;

  if v_study.id is null then
    raise exception 'Study ID or study key is invalid.';
  end if;

  insert into public.admin_profiles (user_id, email)
  values (auth.uid(), coalesce(auth.jwt() ->> 'email', ''))
  on conflict (user_id) do update set email = excluded.email;

  insert into public.study_admins (study_id, admin_user_id)
  values (v_study.id, auth.uid())
  on conflict do nothing;

  return query
  select v_study.id, v_study.study_id;
end;
$$;

create or replace function public.start_participant_session(
  p_public_token text,
  p_first_name text,
  p_last_name text
)
returns table (
  participant_id uuid,
  user_id text,
  study_id text,
  study_name text,
  public_token text,
  template_id uuid,
  template_name text,
  cards jsonb,
  categories jsonb,
  allow_category_editing boolean,
  is_randomized boolean,
  participant_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_study public.studies;
  v_template public.sort_templates;
  v_participant public.participants;
begin
  select * into v_study
  from public.studies
  where studies.public_token = p_public_token;

  if v_study.id is null then
    raise exception 'Invalid study link.';
  end if;

  select * into v_template
  from public.sort_templates
  where sort_templates.study_id = v_study.id
    and sort_templates.is_active = true
  order by created_at desc
  limit 1;

  if v_template.id is null then
    raise exception 'This study does not have an active template.';
  end if;

  insert into public.participants (study_id, first_name, last_name)
  values (v_study.id, trim(p_first_name), trim(p_last_name))
  returning * into v_participant;

  return query
  select
    v_participant.id,
    v_participant.user_id,
    v_study.study_id,
    v_study.study_name,
    v_study.public_token,
    v_template.id,
    v_template.template_name,
    v_template.cards,
    v_template.categories,
    v_template.allow_category_editing,
    v_template.is_randomized,
    concat(v_participant.first_name, ' ', v_participant.last_name);
end;
$$;

create or replace function public.submit_card_sort(
  p_public_token text,
  p_participant_id uuid,
  p_template_id uuid,
  p_result_json jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_study public.studies;
  v_participant public.participants;
  v_submission_id uuid;
begin
  select * into v_study
  from public.studies
  where studies.public_token = p_public_token;

  if v_study.id is null then
    raise exception 'Invalid study link.';
  end if;

  select * into v_participant
  from public.participants
  where participants.id = p_participant_id
    and participants.study_id = v_study.id;

  if v_participant.id is null then
    raise exception 'Participant record not found for this study.';
  end if;

  insert into public.submissions (study_id, participant_id, template_id, result_json)
  values (v_study.id, v_participant.id, p_template_id, p_result_json)
  returning id into v_submission_id;

  return v_submission_id;
end;
$$;

create view public.admin_studies with (security_invoker = true) as
select
  s.id,
  s.study_id,
  s.study_name,
  s.public_token,
  s.created_at,
  (
    select count(*)::int
    from public.submissions sub
    where sub.study_id = s.id
  ) as submission_count
from public.studies s
where public.is_study_admin(s.id);

create view public.study_admin_directory with (security_invoker = true) as
select
  sa.study_id,
  ap.user_id,
  ap.email,
  ap.display_name,
  sa.created_at
from public.study_admins sa
join public.admin_profiles ap on ap.user_id = sa.admin_user_id
where public.is_study_admin(sa.study_id);

create view public.participant_submissions_admin with (security_invoker = true) as
with submission_counts as (
  select participant_id, count(*)::int as submission_count
  from public.submissions
  group by participant_id
)
select
  s.id as study_uuid,
  s.study_id,
  sub.id as submission_id,
  p.id as participant_id,
  p.user_id,
  p.first_name,
  p.last_name,
  concat(p.first_name, ' ', p.last_name) as participant_name,
  sub.template_id,
  sub.result_json,
  sub.submitted_at,
  sc.submission_count
from public.submissions sub
join public.participants p on p.id = sub.participant_id
join public.studies s on s.id = sub.study_id
left join submission_counts sc on sc.participant_id = p.id
where public.is_study_admin(s.id);

alter table public.admin_profiles enable row level security;
alter table public.studies enable row level security;
alter table public.study_admins enable row level security;
alter table public.sort_templates enable row level security;
alter table public.participants enable row level security;
alter table public.submissions enable row level security;

create policy "admins view their profile" on public.admin_profiles
for select using (user_id = auth.uid());

create policy "admins upsert their profile" on public.admin_profiles
for insert with check (user_id = auth.uid());

create policy "admins update their profile" on public.admin_profiles
for update using (user_id = auth.uid());

create policy "study admins view studies" on public.studies
for select using (public.is_study_admin(id));

create policy "study admins view study_admins" on public.study_admins
for select using (public.is_study_admin(study_id));

create policy "study admins view templates" on public.sort_templates
for select using (public.is_study_admin(study_id));

create policy "study admins insert templates" on public.sort_templates
for insert with check (public.is_study_admin(study_id) and created_by = auth.uid());

create policy "study admins update templates" on public.sort_templates
for update using (public.is_study_admin(study_id));

create policy "study admins view participants" on public.participants
for select using (public.is_study_admin(study_id));

create policy "study admins view submissions" on public.submissions
for select using (public.is_study_admin(study_id));

grant usage on schema public to anon, authenticated;
grant select on public.admin_studies to authenticated;
grant select on public.study_admin_directory to authenticated;
grant select on public.participant_submissions_admin to authenticated;
grant execute on function public.get_public_study_context(text) to anon, authenticated;
grant execute on function public.start_participant_session(text, text, text) to anon, authenticated;
grant execute on function public.submit_card_sort(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.create_study_with_template(text, text, text, text, jsonb, jsonb, boolean, boolean) to authenticated;
grant execute on function public.link_admin_to_study(text, text) to authenticated;

grant select on public.studies to authenticated;
grant select on public.study_admins to authenticated;
grant select, insert, update on public.sort_templates to authenticated;
grant select on public.participants to authenticated;
grant select on public.submissions to authenticated;
