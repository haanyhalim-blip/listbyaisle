-- Handy Little Tools – sign-in for ListbyAisle, PackbyBag and DobyToday
-- Run once: Supabase → SQL Editor → New snippet → paste this whole file → Run.
-- Safe to run again.
--
-- In plain English:
--   * Signing in is optional. When you sign in on one of these sites, your list for that site is saved here,
--     under your account, so it opens on any phone or laptop where you sign in.
--   * One row per person per site. Only you can read or change your rows – nobody else, and there is no way to
--     list or search them. The website can only use the three functions below.
--   * Shared list links keep working exactly as before; they are stored separately.

create table if not exists public.hlt_lists (
  owner       uuid not null references auth.users(id) on delete cascade,
  site        text not null check (site in ('listbyaisle', 'packbybag', 'dobytoday')),
  data        jsonb not null,
  updated_at  timestamptz not null default now(),
  primary key (owner, site)
);

alter table public.hlt_lists enable row level security;
revoke all on public.hlt_lists from anon, authenticated;

-- Your saved list for this site, or null.
create or replace function public.hlt_get(p_site text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return null; end if;
  return (select data from public.hlt_lists where owner = auth.uid() and site = p_site);
end $$;

-- Save your list for this site.
create or replace function public.hlt_save(p_site text, p_data jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if octet_length(p_data::text) > 1000000 then raise exception 'list too big'; end if;
  insert into public.hlt_lists (owner, site, data, updated_at) values (auth.uid(), p_site, p_data, now())
  on conflict (owner, site) do update set data = excluded.data, updated_at = now();
  return true;
end $$;

-- Remove your saved list for this site.
create or replace function public.hlt_delete(p_site text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  delete from public.hlt_lists where owner = auth.uid() and site = p_site;
  return found;
end $$;

revoke all on function public.hlt_get(text), public.hlt_save(text, jsonb), public.hlt_delete(text) from public;
grant execute on function public.hlt_get(text), public.hlt_save(text, jsonb), public.hlt_delete(text) to authenticated;

-- Check it worked: one row, "hlt_lists", with rls_on = true.
select tablename, rowsecurity as rls_on from pg_tables where schemaname = 'public' and tablename = 'hlt_lists';
