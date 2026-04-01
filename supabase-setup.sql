-- ============================================================
-- LandFlow CRM — Supabase Database Setup
-- Paste this entire file into Supabase → SQL Editor → Run
-- ============================================================

-- LOANS
create table if not exists loans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  borrower text,
  buyer_company text,
  seller text,
  phone text,
  email text,
  ssn text,
  county text,
  parcel text,
  address text,
  legal_desc text,
  loan_amount numeric,
  sale_price numeric,
  down_payment numeric,
  rate numeric,
  term integer,
  balloon text,
  orig_date date,
  first_pay_date date,
  status text default 'current',
  investor text,
  inv_contact text,
  inv_date date,
  inv_price numeric,
  nb_name text,
  nb_business text,
  nb_phone text,
  nb_email text,
  nb_address text,
  notes text,
  sold boolean default false,
  created_at timestamptz default now()
);

-- PAYMENTS
create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  loan_id uuid references loans(id) on delete cascade,
  date date,
  amount numeric,
  type text default 'regular',
  ref text,
  notes text,
  created_at timestamptz default now()
);

-- INVESTORS
create table if not exists investors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text,
  contact text,
  phone text,
  email text,
  notes text,
  created_at timestamptz default now()
);

-- INVOICES
create table if not exists invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  loan_id uuid references loans(id) on delete cascade,
  borrower text,
  email text,
  period text,
  due_date date,
  amount numeric,
  notes text,
  status text default 'pending',
  sent_at timestamptz,
  created_at timestamptz default now()
);

-- VAULT FILES (documents per parcel)
create table if not exists vault_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  loan_id uuid references loans(id) on delete cascade,
  cat_id text,
  name text,
  size bigint,
  type text,
  data text,
  book_page text,
  notes text,
  created_at timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY — users can only see their own data
-- ============================================================
alter table loans enable row level security;
alter table payments enable row level security;
alter table investors enable row level security;
alter table invoices enable row level security;
alter table vault_files enable row level security;

-- LOANS policies
create policy "Users see own loans" on loans for select using (auth.uid() = user_id);
create policy "Users insert own loans" on loans for insert with check (auth.uid() = user_id);
create policy "Users update own loans" on loans for update using (auth.uid() = user_id);
create policy "Users delete own loans" on loans for delete using (auth.uid() = user_id);

-- PAYMENTS policies
create policy "Users see own payments" on payments for select using (auth.uid() = user_id);
create policy "Users insert own payments" on payments for insert with check (auth.uid() = user_id);
create policy "Users update own payments" on payments for update using (auth.uid() = user_id);
create policy "Users delete own payments" on payments for delete using (auth.uid() = user_id);

-- INVESTORS policies
create policy "Users see own investors" on investors for select using (auth.uid() = user_id);
create policy "Users insert own investors" on investors for insert with check (auth.uid() = user_id);
create policy "Users update own investors" on investors for update using (auth.uid() = user_id);
create policy "Users delete own investors" on investors for delete using (auth.uid() = user_id);

-- INVOICES policies
create policy "Users see own invoices" on invoices for select using (auth.uid() = user_id);
create policy "Users insert own invoices" on invoices for insert with check (auth.uid() = user_id);
create policy "Users update own invoices" on invoices for update using (auth.uid() = user_id);
create policy "Users delete own invoices" on invoices for delete using (auth.uid() = user_id);

-- VAULT FILES policies
create policy "Users see own vault files" on vault_files for select using (auth.uid() = user_id);
create policy "Users insert own vault files" on vault_files for insert with check (auth.uid() = user_id);
create policy "Users update own vault files" on vault_files for update using (auth.uid() = user_id);
create policy "Users delete own vault files" on vault_files for delete using (auth.uid() = user_id);
