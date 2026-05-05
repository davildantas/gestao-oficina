-- =============================================================
-- MIGRAÇÃO: Sistema de Convites
-- Execute no SQL Editor do Supabase Dashboard
-- =============================================================

-- 1. Expandir roles válidos no profiles (adicionar socio, assistente, colaborador)
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('dono','socio','gerente','operador','assistente','colaborador'));

-- 2. Tabela de convites
create table if not exists public.convites (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  codigo       text not null unique,
  role         text not null default 'operador'
    check (role in ('dono','socio','gerente','operador','assistente','colaborador')),
  criado_por   uuid references auth.users(id) on delete set null,
  usado_por    uuid references auth.users(id) on delete set null,
  usado_em     timestamptz,
  expira_em    timestamptz not null default (now() + interval '7 days'),
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now()
);
alter table public.convites enable row level security;
create index if not exists idx_convites_codigo on public.convites(codigo);
create index if not exists idx_convites_workspace on public.convites(workspace_id);

-- 3. RLS: membros veem convites do seu workspace
create policy "convites_select" on public.convites
  for select using (workspace_id = public.meu_workspace_id());

create policy "convites_insert" on public.convites
  for insert with check (
    workspace_id = public.meu_workspace_id()
    and exists (
      select 1 from public.profiles
      where id = auth.uid()
        and workspace_id = public.meu_workspace_id()
        and role in ('dono','gerente','socio')
    )
  );

create policy "convites_update" on public.convites
  for update using (
    workspace_id = public.meu_workspace_id()
    and exists (
      select 1 from public.profiles
      where id = auth.uid()
        and workspace_id = public.meu_workspace_id()
        and role in ('dono','gerente','socio')
    )
  );

-- 4. RPC: gerar código de convite (chamado pelo dono/gerente)
create or replace function public.gerar_convite(
  p_workspace_id uuid,
  p_role text default 'operador'
) returns text language plpgsql security definer
set search_path = public
as $$
declare
  v_codigo text;
  v_caller_role text;
begin
  select role into v_caller_role
  from public.profiles
  where id = auth.uid() and workspace_id = p_workspace_id;

  if v_caller_role is null or v_caller_role not in ('dono','gerente','socio') then
    raise exception 'Sem permissão para gerar convites';
  end if;

  loop
    v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.convites where codigo = v_codigo);
  end loop;

  insert into public.convites(workspace_id, codigo, role, criado_por)
  values (p_workspace_id, v_codigo, p_role, auth.uid());

  return v_codigo;
end;
$$;

-- 5. RPC: resgatar convite (chamado pelo novo usuário após signup)
create or replace function public.resgatar_convite(
  p_user_id uuid,
  p_codigo text,
  p_nome text,
  p_username text
) returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_convite record;
begin
  select * into v_convite
  from public.convites
  where codigo = upper(trim(p_codigo))
    and ativo = true
    and usado_por is null
    and expira_em > now();

  if not found then
    raise exception 'Código inválido, expirado ou já utilizado';
  end if;

  if exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Este usuário já pertence a uma oficina';
  end if;

  perform public.adicionar_membro(
    p_user_id, v_convite.workspace_id,
    p_nome, p_username, v_convite.role
  );

  update public.convites
  set usado_por = p_user_id, usado_em = now(), ativo = false
  where id = v_convite.id;

  return v_convite.workspace_id;
end;
$$;
