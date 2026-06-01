-- =====================================================================
-- Migration: FinControl — Fase 2 (contas a pagar/receber, contas
-- bancárias e centros de custo) → Supabase
-- Data: 2026-05-31
-- RLS: financeiro (dono/socio), consistente com o livro financeiro.
-- Depende de public.tem_financeiro() / public.meu_workspace_id().
-- =====================================================================

-- ─── CONTAS A PAGAR / RECEBER (boletos) ──────────────────────────────
create table if not exists public.contas_fin (
  id             uuid primary key default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  nome           text not null,
  tipo           text not null default 'pagar' check (tipo in ('pagar','receber')),
  valor_parcela  numeric(12,2) not null default 0,
  total_parcelas integer not null default 1,
  parcelas_pagas integer not null default 0,
  vencimento     date,
  desconto       numeric(12,2) not null default 0,
  alerta_dias    integer not null default 3,
  categoria      text,
  obs            text,
  cliente_id     uuid references public.clientes(id) on delete set null,
  cliente_nome   text,
  fc_id          text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
alter table public.contas_fin enable row level security;
drop policy if exists "contas_fin_admin" on public.contas_fin;
create policy "contas_fin_admin" on public.contas_fin for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create index if not exists idx_contas_fin_ws on public.contas_fin(workspace_id, vencimento);
create unique index if not exists uniq_contas_fin_fcid
  on public.contas_fin(workspace_id, fc_id) where fc_id is not null;

-- ─── CONTAS BANCÁRIAS ────────────────────────────────────────────────
create table if not exists public.contas_bancarias (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  banco         text not null,
  tipo          text,
  saldo_inicial numeric(12,2) not null default 0,
  fc_id         text,
  criado_em     timestamptz not null default now()
);
alter table public.contas_bancarias enable row level security;
drop policy if exists "contas_banc_admin" on public.contas_bancarias;
create policy "contas_banc_admin" on public.contas_bancarias for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create unique index if not exists uniq_contas_banc_fcid
  on public.contas_bancarias(workspace_id, fc_id) where fc_id is not null;

-- ─── CENTROS DE CUSTO ────────────────────────────────────────────────
create table if not exists public.centros_custo (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  unique (workspace_id, nome)
);
alter table public.centros_custo enable row level security;
drop policy if exists "centros_admin" on public.centros_custo;
create policy "centros_admin" on public.centros_custo for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());

-- ─── Triggers atualizado_em / Realtime ───────────────────────────────
drop trigger if exists trg_contas_fin_updated on public.contas_fin;
create trigger trg_contas_fin_updated before update on public.contas_fin
  for each row execute function public.set_atualizado_em();

do $$ begin
  begin alter publication supabase_realtime add table public.contas_fin;
  exception when duplicate_object then null; end;
end $$;
