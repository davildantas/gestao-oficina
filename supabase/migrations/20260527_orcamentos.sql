-- =============================================================
-- MÓDULO DE ORÇAMENTOS COMPLETO
-- =============================================================

-- ─── ORÇAMENTOS ───────────────────────────────────────────────
create table public.orcamentos (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid not null references public.workspaces(id) on delete cascade,
  numero          bigint not null,
  cliente_id      uuid references public.clientes(id) on delete set null,
  tipo_veiculo    text default 'sedan',
  veiculo_modelo  text,
  veiculo_ano     text,
  veiculo_placa   text,
  veiculo_km      numeric(10,0),
  veiculo_motor   text,
  veiculo_cor     text,
  veiculo_chassi  text,
  entrada_guincho boolean not null default false,
  possui_seguro   boolean not null default false,
  observacoes     text,
  desconto_tipo   text not null default 'porcentagem' check (desconto_tipo in ('porcentagem','valor')),
  desconto_valor  numeric(12,2) not null default 0,
  condicao_pagamento text,
  status          text not null default 'aguardando' check (status in ('aguardando','aprovado','cancelado','agendado')),
  checklist_avarias jsonb not null default '[]'::jsonb,
  checklist_vistoria jsonb not null default '{}'::jsonb,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
alter table public.orcamentos enable row level security;
create policy "orcamentos_workspace" on public.orcamentos
  for all using (workspace_id = (select workspace_id from public.profiles where id = auth.uid()));
create index on public.orcamentos(workspace_id);
create index on public.orcamentos(cliente_id);
create index on public.orcamentos(status);

-- ─── CATÁLOGO DE SERVIÇOS ─────────────────────────────────────
create table public.catalogo_servicos (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  descricao    text,
  instrucoes   text,
  valor        numeric(12,2) not null default 0,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.catalogo_servicos enable row level security;
create policy "catalogo_workspace" on public.catalogo_servicos
  for all using (workspace_id = (select workspace_id from public.profiles where id = auth.uid()));
create index on public.catalogo_servicos(workspace_id);

-- ─── SERVIÇOS DO ORÇAMENTO ────────────────────────────────────
create table public.orcamento_servicos (
  id           uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references public.orcamentos(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  descricao    text,
  instrucoes   text,
  valor        numeric(12,2) not null default 0,
  catalogo_id  uuid references public.catalogo_servicos(id) on delete set null,
  ordem        integer not null default 0
);
alter table public.orcamento_servicos enable row level security;
create policy "orc_servicos_workspace" on public.orcamento_servicos
  for all using (workspace_id = (select workspace_id from public.profiles where id = auth.uid()));
create index on public.orcamento_servicos(orcamento_id);

-- ─── LANÇAMENTOS DO ORÇAMENTO ─────────────────────────────────
create table public.orcamento_lancamentos (
  id           uuid primary key default gen_random_uuid(),
  orcamento_id uuid not null references public.orcamentos(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  descricao    text,
  valor        numeric(12,2) not null,
  forma_pgto   text,
  data         date,
  recebido     boolean not null default false,
  criado_em    timestamptz not null default now()
);
alter table public.orcamento_lancamentos enable row level security;
create policy "orc_lancamentos_workspace" on public.orcamento_lancamentos
  for all using (workspace_id = (select workspace_id from public.profiles where id = auth.uid()));
create index on public.orcamento_lancamentos(orcamento_id);
