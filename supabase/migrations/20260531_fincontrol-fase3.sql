-- =====================================================================
-- Migration: FinControl — Fase 3 (categorias + preservação do legado)
-- Data: 2026-05-31
-- - Categorias: serão mescladas em categorias_financeiras (já existente)
--   pelo importador do cliente (sem mudança de schema).
-- - Recorrências/regras/pessoas/vendedores: baixo volume e sem motor nativo;
--   preservados numa tabela genérica para não se perderem ao aposentar o iframe.
-- RLS: financeiro (dono/socio).
-- =====================================================================

create table if not exists public.fincontrol_legado (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  tipo         text not null,                 -- 'recorrencia' | 'regra' | 'pessoa' | 'vendedor'
  fc_id        text,
  dados        jsonb not null default '{}'::jsonb,
  criado_em    timestamptz not null default now()
);
alter table public.fincontrol_legado enable row level security;
drop policy if exists "fc_legado_admin" on public.fincontrol_legado;
create policy "fc_legado_admin" on public.fincontrol_legado for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create index if not exists idx_fc_legado_ws on public.fincontrol_legado(workspace_id, tipo);
create unique index if not exists uniq_fc_legado
  on public.fincontrol_legado(workspace_id, tipo, fc_id) where fc_id is not null;
