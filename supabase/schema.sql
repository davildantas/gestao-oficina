-- =============================================================
-- OFICINA MANAGER — Supabase Schema
-- =============================================================
-- Multi-tenant: cada oficina é um "workspace".
-- Todos os usuários pertencem a um workspace via profiles.workspace_id.
-- RLS garante que cada usuário veja apenas dados do seu workspace.
-- =============================================================

-- ─── EXTENSÕES ───────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ─── WORKSPACES ──────────────────────────────────────────────
create table public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  slug        text unique not null,
  criado_em   timestamptz not null default now()
);
alter table public.workspaces enable row level security;

-- ─── PROFILES (extensão de auth.users) ───────────────────────
-- role: 'dono' | 'gerente' | 'operador'
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  username     text not null,
  role         text not null default 'operador' check (role in ('dono','gerente','operador')),
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- ─── COLABORADORES ────────────────────────────────────────────
create table public.colaboradores (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  funcao       text,
  salario      numeric(12,2) not null default 0,
  comissao_pct numeric(5,2) not null default 0,
  telefone     text,
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.colaboradores enable row level security;
create index on public.colaboradores(workspace_id);

-- ─── CLIENTES ─────────────────────────────────────────────────
create table public.clientes (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  telefone     text,
  email        text,
  cpf_cnpj     text,
  endereco     text,
  obs          text,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.clientes enable row level security;
create index on public.clientes(workspace_id);
create index on public.clientes(nome);

-- ─── VEÍCULOS / ORDENS DE SERVIÇO ────────────────────────────
-- Status (kanban): aguardando | em-andamento | aguardando-pecas | pronto | entregue | cancelado
create table public.veiculos (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  cliente_id    uuid references public.clientes(id) on delete set null,
  placa         text,
  modelo        text,
  cor           text,
  ano           text,
  km            numeric(10,0),
  servico       text,
  descricao     text,
  status        text not null default 'aguardando' check (status in ('aguardando','em-andamento','aguardando-pecas','pronto','entregue','cancelado')),
  responsavel_id uuid references public.colaboradores(id) on delete set null,
  valor_orcamento numeric(12,2),
  valor_final    numeric(12,2),
  nivel_combustivel integer check (nivel_combustivel between 0 and 8),
  entrada_em    timestamptz,
  saida_em      timestamptz,
  prazo         date,
  nota_numero   integer,
  fc_lanc_id    uuid,
  meta          jsonb not null default '{}'::jsonb,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.veiculos enable row level security;
create index on public.veiculos(workspace_id);
create index on public.veiculos(status);
create index on public.veiculos(cliente_id);

-- ─── ITENS DO ORÇAMENTO (por veículo) ────────────────────────
create table public.orcamento_itens (
  id           uuid primary key default gen_random_uuid(),
  veiculo_id   uuid not null references public.veiculos(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  descricao    text not null,
  quantidade   numeric(10,3) not null default 1,
  preco_unit   numeric(12,2) not null default 0,
  ordem        integer not null default 0
);
alter table public.orcamento_itens enable row level security;
create index on public.orcamento_itens(veiculo_id);

-- ─── FOTOS (links para Supabase Storage) ─────────────────────
create table public.fotos (
  id           uuid primary key default gen_random_uuid(),
  veiculo_id   uuid not null references public.veiculos(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  storage_path text not null,
  url          text,
  criado_em    timestamptz not null default now()
);
alter table public.fotos enable row level security;
create index on public.fotos(veiculo_id);

-- ─── AGENDA ───────────────────────────────────────────────────
create table public.agenda (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  cliente_id   uuid references public.clientes(id) on delete set null,
  veiculo_id   uuid references public.veiculos(id) on delete set null,
  titulo       text not null,
  data         date not null,
  hora         text,
  tipo         text,
  obs          text,
  criado_em    timestamptz not null default now()
);
alter table public.agenda enable row level security;
create index on public.agenda(workspace_id, data);

-- ─── ESTOQUE ─────────────────────────────────────────────────
create table public.estoque (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome         text not null,
  quantidade   numeric(10,3) not null default 0,
  unidade      text not null default 'un',
  preco_custo  numeric(12,2),
  estoque_min  numeric(10,3) not null default 0,
  categoria    text,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.estoque enable row level security;
create index on public.estoque(workspace_id);

-- ─── PAGAMENTOS / CAIXA ───────────────────────────────────────
-- tipo: 'entrada' | 'saida'
create table public.pagamentos (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  veiculo_id   uuid references public.veiculos(id) on delete set null,
  tipo         text not null check (tipo in ('entrada','saida')),
  descricao    text not null,
  valor        numeric(12,2) not null,
  forma        text,
  categoria    text,
  data         date not null default current_date,
  obs          text,
  criado_em    timestamptz not null default now()
);
alter table public.pagamentos enable row level security;
create index on public.pagamentos(workspace_id, data);
create index on public.pagamentos(veiculo_id);

-- ─── PARCELAS ─────────────────────────────────────────────────
create table public.parcelas (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  veiculo_id   uuid references public.veiculos(id) on delete set null,
  cliente_id   uuid references public.clientes(id) on delete set null,
  descricao    text,
  valor        numeric(12,2) not null,
  vencimento   date not null,
  pago         boolean not null default false,
  pago_em      timestamptz,
  criado_em    timestamptz not null default now()
);
alter table public.parcelas enable row level security;
create index on public.parcelas(workspace_id, vencimento);

-- ─── LANÇAMENTOS FINANCEIROS (FinControl) ────────────────────
-- tipo: 'entrada' | 'saida'
create table public.lancamentos (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  tipo         text not null check (tipo in ('entrada','saida')),
  descricao    text not null,
  valor        numeric(12,2) not null,
  categoria    text,
  data         date not null default current_date,
  obs          text,
  veiculo_id   uuid references public.veiculos(id) on delete set null,
  criado_em    timestamptz not null default now()
);
alter table public.lancamentos enable row level security;
create index on public.lancamentos(workspace_id, data);

-- ─── CATEGORIAS FINANCEIRAS ───────────────────────────────────
create table public.categorias_financeiras (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  tipo         text not null check (tipo in ('entrada','saida')),
  nome         text not null,
  unique (workspace_id, tipo, nome)
);
alter table public.categorias_financeiras enable row level security;
create index on public.categorias_financeiras(workspace_id);

-- ─── METAS ────────────────────────────────────────────────────
create table public.metas (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  ano          integer not null,
  mes          integer not null check (mes between 1 and 12),
  receita_meta numeric(12,2),
  os_meta      integer,
  unique (workspace_id, ano, mes)
);
alter table public.metas enable row level security;

-- ─── NOTAS INTERNAS ───────────────────────────────────────────
create table public.notas (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  veiculo_id   uuid references public.veiculos(id) on delete cascade,
  autor_id     uuid references public.profiles(id) on delete set null,
  texto        text not null,
  criado_em    timestamptz not null default now()
);
alter table public.notas enable row level security;
create index on public.notas(veiculo_id);

-- ─── SATISFAÇÃO DO CLIENTE ────────────────────────────────────
create table public.satisfacoes (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  veiculo_id   uuid references public.veiculos(id) on delete set null,
  cliente_id   uuid references public.clientes(id) on delete set null,
  nota         integer not null check (nota between 1 and 5),
  comentario   text,
  criado_em    timestamptz not null default now()
);
alter table public.satisfacoes enable row level security;

-- ─── FILA DE ESPERA ───────────────────────────────────────────
create table public.fila (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  cliente_nome text not null,
  servico      text,
  telefone     text,
  prioridade   integer not null default 0,
  criado_em    timestamptz not null default now()
);
alter table public.fila enable row level security;

-- ─── AUDITORIA ────────────────────────────────────────────────
create table public.auditoria (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid references public.profiles(id) on delete set null,
  username     text,
  acao         text not null,
  detalhe      text,
  criado_em    timestamptz not null default now()
);
alter table public.auditoria enable row level security;
create index on public.auditoria(workspace_id, criado_em desc);

-- ─── CONFIGURAÇÕES DO WORKSPACE ───────────────────────────────
create table public.config (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  nome_oficina text not null default 'Minha Oficina',
  cat_servico  text not null default 'Serviços',
  cat_pecas    text not null default 'Compra de peças',
  cat_salario  text not null default 'Folha de pagamento',
  nota_seq     integer not null default 0,
  dados        jsonb not null default '{}'
);
alter table public.config enable row level security;

-- =============================================================
-- RLS POLICIES
-- =============================================================
-- Helper: retorna workspace_id do usuário autenticado atual
create or replace function public.meu_workspace_id()
returns uuid language sql stable security definer
set search_path = public
as $$
  select workspace_id from public.profiles where id = auth.uid()
$$;

-- Macro para criar políticas de workspace em todas as tabelas
-- (aplicada manualmente abaixo por tabela)

-- WORKSPACES: cada usuário vê apenas o seu
create policy "workspace_select" on public.workspaces
  for select using (id = public.meu_workspace_id());

-- PROFILES
create policy "profiles_select" on public.profiles
  for select using (workspace_id = public.meu_workspace_id());
create policy "profiles_insert" on public.profiles
  for insert with check (workspace_id = public.meu_workspace_id());
create policy "profiles_update" on public.profiles
  for update using (workspace_id = public.meu_workspace_id());

-- COLABORADORES
create policy "colab_all" on public.colaboradores
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- CLIENTES
create policy "clientes_all" on public.clientes
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- VEÍCULOS
create policy "veiculos_all" on public.veiculos
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- ORCAMENTO_ITENS
create policy "orc_all" on public.orcamento_itens
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- FOTOS
create policy "fotos_all" on public.fotos
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- AGENDA
create policy "agenda_all" on public.agenda
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- ESTOQUE
create policy "estoque_all" on public.estoque
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- PAGAMENTOS
create policy "pagamentos_all" on public.pagamentos
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- PARCELAS
create policy "parcelas_all" on public.parcelas
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- LANCAMENTOS
create policy "lanc_all" on public.lancamentos
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- CATEGORIAS
create policy "cats_all" on public.categorias_financeiras
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- METAS
create policy "metas_all" on public.metas
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- NOTAS
create policy "notas_all" on public.notas
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- SATISFAÇÕES
create policy "satisf_all" on public.satisfacoes
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- FILA
create policy "fila_all" on public.fila
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- AUDITORIA (somente leitura para todos; insert via função)
create policy "audit_select" on public.auditoria
  for select using (workspace_id = public.meu_workspace_id());
create policy "audit_insert" on public.auditoria
  for insert with check (workspace_id = public.meu_workspace_id());

-- CONFIG
create policy "config_all" on public.config
  for all using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());

-- =============================================================
-- FUNÇÃO: criar workspace + perfil admin em uma transação
-- =============================================================
create or replace function public.criar_workspace(
  p_user_id    uuid,
  p_nome       text,
  p_slug       text,
  p_user_nome  text,
  p_username   text
) returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_ws_id uuid;
begin
  insert into public.workspaces(nome, slug)
  values (p_nome, p_slug)
  returning id into v_ws_id;

  insert into public.profiles(id, workspace_id, nome, username, role)
  values (p_user_id, v_ws_id, p_user_nome, p_username, 'dono');

  insert into public.config(workspace_id, nome_oficina)
  values (v_ws_id, p_nome);

  return v_ws_id;
end;
$$;

-- =============================================================
-- FUNÇÃO: convidar usuário para um workspace existente
-- Chamada após o novo usuário confirmar o e-mail.
-- =============================================================
create or replace function public.adicionar_membro(
  p_user_id    uuid,
  p_workspace_id uuid,
  p_nome       text,
  p_username   text,
  p_role       text default 'operador'
) returns void language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, workspace_id, nome, username, role)
  values (p_user_id, p_workspace_id, p_nome, p_username, p_role)
  on conflict (id) do update
    set workspace_id = excluded.workspace_id,
        nome = excluded.nome,
        username = excluded.username,
        role = excluded.role;
end;
$$;

-- =============================================================
-- TRIGGER: atualizado_em automático
-- =============================================================
create or replace function public.set_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

create trigger trg_colabs_updated    before update on public.colaboradores    for each row execute function public.set_atualizado_em();
create trigger trg_clientes_updated  before update on public.clientes         for each row execute function public.set_atualizado_em();
create trigger trg_veiculos_updated  before update on public.veiculos         for each row execute function public.set_atualizado_em();
create trigger trg_estoque_updated   before update on public.estoque          for each row execute function public.set_atualizado_em();

-- =============================================================
-- REALTIME: habilitar publicação nas tabelas principais
-- =============================================================
alter publication supabase_realtime add table public.veiculos;
alter publication supabase_realtime add table public.pagamentos;
alter publication supabase_realtime add table public.estoque;
alter publication supabase_realtime add table public.agenda;
alter publication supabase_realtime add table public.fila;
alter publication supabase_realtime add table public.notas;
