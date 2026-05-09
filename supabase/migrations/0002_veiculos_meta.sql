-- =============================================================
-- 0002_veiculos_meta.sql
-- Adiciona coluna `meta jsonb` em `veiculos` para guardar campos
-- da UI que não têm coluna dedicada: vistoria, tempoTrabalhado,
-- registradoPor, orcamentoStatus, timestampEntrada, telefone do
-- cliente no momento da entrada, etc.
--
-- Aplicar no Supabase: SQL Editor → cole o conteúdo → Run.
-- Idempotente: pode rodar várias vezes sem efeito colateral.
-- =============================================================

alter table public.veiculos
  add column if not exists meta jsonb not null default '{}'::jsonb;

comment on column public.veiculos.meta is
  'Campos auxiliares da UI sem coluna dedicada (vistoria, tempoTrabalhado, registradoPor, orcamentoStatus, etc).';
