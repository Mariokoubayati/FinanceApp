-- Run once in the Supabase SQL Editor on an existing database.
-- schema.sql originally left the budgets table without Row Level Security,
-- so anyone holding the public anon key could read or write every budget row.
-- Safe to run more than once.

alter table public.budgets enable row level security;

drop policy if exists "budgets_all" on public.budgets;
create policy "budgets_all" on public.budgets for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
