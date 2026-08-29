-- =====================================================
-- FinanceTracker — Supabase Schema  (idempotent)
-- Safe to run multiple times. Drops and recreates all.
-- =====================================================

-- ─────────────────────────────────────────
-- CLEAN SLATE (drop in reverse dependency order)
-- ─────────────────────────────────────────
drop table if exists public.savings_goals  cascade;
drop table if exists public.transactions   cascade;
drop table if exists public.categories     cascade;
drop table if exists public.accounts       cascade;
drop table if exists public.profiles       cascade;

drop function if exists public.handle_new_user()         cascade;
drop function if exists public.update_updated_at_column() cascade;

-- ─────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────
-- PROFILES
-- ─────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  currency    text not null default 'USD',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────
-- ACCOUNTS
-- ─────────────────────────────────────────
create table public.accounts (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  type        text not null check (type in ('bank','cash','credit','savings')),
  balance     numeric(14,2) not null default 0,
  currency    text not null default 'USD',
  color       text not null default '#5B8DEF',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────
-- CATEGORIES
-- ─────────────────────────────────────────
create table public.categories (
  id       uuid primary key default uuid_generate_v4(),
  user_id  uuid references auth.users(id) on delete cascade,
  name     text not null,
  type     text not null check (type in ('income','expense')),
  icon     text not null default 'circle.fill',
  color    text not null default '#5B8DEF'
);

insert into public.categories (name, type, icon, color) values
  -- Income
  ('Salary',        'income',  'briefcase.fill',              '#34C759'),
  ('Freelance',     'income',  'laptopcomputer',              '#30D158'),
  ('Investment',    'income',  'chart.line.uptrend.xyaxis',   '#64D2FF'),
  ('Gift',          'income',  'gift.fill',                   '#5E5CE6'),
  ('Other Income',  'income',  'plus.circle.fill',            '#8E8E93'),
  -- Expense
  ('University',    'expense', 'graduationcap.fill',          '#5AC8FA'),
  ('Entertainment', 'expense', 'tv.fill',                     '#0A84FF'),
  ('Food',          'expense', 'fork.knife',                  '#FF9F0A'),
  ('Health',        'expense', 'heart.fill',                  '#FF2D55'),
  ('Live',          'expense', 'house.fill',                  '#34C759'),
  ('Shopping',      'expense', 'bag.fill',                    '#BF5AF2'),
  ('Transport',     'expense', 'tram.fill',                   '#FF6B6B'),
  ('Sport',         'expense', 'figure.run',                  '#30D158'),
  ('Subscription',  'expense', 'arrow.2.circlepath',          '#5E5CE6'),
  ('Bills',         'expense', 'doc.text.fill',               '#FF453A'),
  ('Other',         'expense', 'ellipsis.circle.fill',        '#8E8E93'),
  ('Car',           'expense', 'car.fill',                    '#FF9500'),
  ('Gifts',         'expense', 'gift.fill',                   '#FF6CAE');

-- ─────────────────────────────────────────
-- TRANSACTIONS
-- ─────────────────────────────────────────
create table public.transactions (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  account_id   uuid not null references public.accounts(id) on delete cascade,
  category_id  uuid references public.categories(id),
  type         text not null check (type in ('income','expense')),
  amount       numeric(14,2) not null check (amount > 0),
  description  text not null,
  note         text,
  date         date not null default current_date,
  created_at   timestamptz not null default now()
);

-- ─────────────────────────────────────────
-- BUDGETS
-- ─────────────────────────────────────────
create table public.budgets (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  category_id    uuid not null references public.categories(id) on delete cascade,
  monthly_limit  numeric(14,2) not null check (monthly_limit > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique(user_id, category_id)
);

-- ─────────────────────────────────────────
-- SAVINGS GOALS
-- ─────────────────────────────────────────
create table public.savings_goals (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  target_amount   numeric(14,2) not null check (target_amount > 0),
  current_amount  numeric(14,2) not null default 0,
  target_date     date,
  icon            text not null default 'star.fill',
  color           text not null default '#FFD60A',
  is_completed    boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ─────────────────────────────────────────
-- AUTO-UPDATE updated_at
-- ─────────────────────────────────────────
create or replace function public.update_updated_at_column()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at      on public.profiles;
drop trigger if exists accounts_updated_at      on public.accounts;
drop trigger if exists budgets_updated_at       on public.budgets;
drop trigger if exists savings_goals_updated_at on public.savings_goals;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.update_updated_at_column();

create trigger accounts_updated_at
  before update on public.accounts
  for each row execute function public.update_updated_at_column();

create trigger budgets_updated_at
  before update on public.budgets
  for each row execute function public.update_updated_at_column();

create trigger savings_goals_updated_at
  before update on public.savings_goals
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────
alter table public.profiles      enable row level security;
alter table public.accounts      enable row level security;
alter table public.categories    enable row level security;
alter table public.transactions  enable row level security;
alter table public.savings_goals enable row level security;

-- profiles
create policy "profiles_all" on public.profiles for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- accounts
create policy "accounts_all" on public.accounts for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- categories: read system defaults + own; write only own
create policy "categories_select" on public.categories for select
  using (user_id is null or auth.uid() = user_id);

create policy "categories_insert" on public.categories for insert
  with check (auth.uid() = user_id);

create policy "categories_update" on public.categories for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "categories_delete" on public.categories for delete
  using (auth.uid() = user_id);

-- transactions
create policy "transactions_all" on public.transactions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- savings goals
create policy "savings_goals_all" on public.savings_goals for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
