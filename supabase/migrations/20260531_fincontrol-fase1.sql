-- =====================================================================
-- Migration: FinControl — Fase 1 (lançamentos unificados em `lancamentos`)
-- Data: 2026-05-31
-- Estende a tabela lancamentos com os campos do FinControl e prepara a
-- importação idempotente dos lançamentos legados (fc_lanc).
-- Aditiva e segura (add column if not exists).
-- =====================================================================

alter table public.lancamentos add column if not exists forma   text;
alter table public.lancamentos add column if not exists centro  text;          -- centro de custo (texto por ora)
alter table public.lancamentos add column if not exists origem  text;          -- 'oficina' | 'fincontrol' | null
alter table public.lancamentos add column if not exists fc_id   text;          -- id original no FinControl (dedupe/idempotência)
alter table public.lancamentos add column if not exists meta    jsonb not null default '{}'::jsonb;

-- Idempotência da importação: um mesmo lançamento do FinControl (fc_id) não
-- pode ser importado duas vezes no mesmo workspace. (NULLs não conflitam, então
-- os lançamentos gerados pela oficina — fc_id null — não são afetados.)
create unique index if not exists uniq_lancamentos_ws_fcid
  on public.lancamentos(workspace_id, fc_id)
  where fc_id is not null;
