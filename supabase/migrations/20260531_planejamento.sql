-- =====================================================================
-- Migration: Planejamento da Semana → Supabase
-- Data: 2026-05-31
-- Substitui o armazenamento em localStorage (om_plan_*) por tabelas no
-- banco, para sincronizar entre dispositivos/usuários.
-- Decisão D3: blob jsonb (notas/metas/config) + tabela de tarefas.
-- =====================================================================

-- ─── Blob por workspace: notas diárias, metas, config ────────────────
create table if not exists public.planejamento (
  workspace_id  uuid primary key references public.workspaces(id) on delete cascade,
  dados         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);
alter table public.planejamento enable row level security;
drop policy if exists "plan_all" on public.planejamento;
create policy "plan_all" on public.planejamento for all
  using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- ─── Tarefas da semana (lista editada por vários usuários) ───────────
create table if not exists public.planejamento_tarefas (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  sem_key      text not null,                 -- ex.: '2026-05-25' (segunda da semana)
  titulo       text not null,
  feito        boolean not null default false,
  feito_em     date,
  meta         jsonb not null default '{}'::jsonb,  -- { pri, cat, obs }
  criado_em    timestamptz not null default now()
);
alter table public.planejamento_tarefas enable row level security;
drop policy if exists "plan_tarefas_all" on public.planejamento_tarefas;
create policy "plan_tarefas_all" on public.planejamento_tarefas for all
  using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());
create index if not exists idx_plan_tarefas_ws  on public.planejamento_tarefas(workspace_id, sem_key);

-- ─── Realtime: sincronizar tarefas entre usuários ───────────────────
do $$ begin
  begin
    alter publication supabase_realtime add table public.planejamento_tarefas;
  exception when duplicate_object then null;
  end;
end $$;
