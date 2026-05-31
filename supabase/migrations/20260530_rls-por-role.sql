-- =====================================================================
-- Migration: RLS por ROLE (controle de acesso no banco)
-- Data: 2026-05-30
-- Base: supabase/RLS-PROPOSAL.md
--
-- ⚠️  ATENÇÃO — A SEÇÃO 5 (split de colaboradores) É DESTRUTIVA:
--     ela move colunas sensíveis para colaboradores_remuneracao e
--     DROPA as colunas originais de colaboradores. FAÇA BACKUP antes
--     (Dashboard → Database → Backups, ou `select * from colaboradores`).
--     A cópia ocorre ANTES do drop e só toca colunas que existem.
-- =====================================================================

-- ─── 1. HELPERS DE PAPEL ─────────────────────────────────────────────
-- meu_role() já existe (migration 20260530_correcoes-rapidas.sql).
create or replace function public.tem_financeiro()
  returns boolean language sql stable security definer set search_path = public
  as $$ select public.meu_role() in ('dono','socio') $$;

create or replace function public.tem_gestao()
  returns boolean language sql stable security definer set search_path = public
  as $$ select public.meu_role() in ('dono','socio','gerente') $$;

-- ─── 2. FINANCEIRO — policies assimétricas ───────────────────────────
-- Inserção ABERTA (fluxos operacionais geram receita/despesa automática),
-- mas leitura/edição/exclusão só ADMIN (dono/socio).
do $$
declare t text;
begin
  foreach t in array array['lancamentos','pagamentos','parcelas'] loop
    execute format('drop policy if exists %I on public.%I', t||'_all', t);
    execute format('drop policy if exists %I on public.%I', 'lanc_all', t);  -- nome antigo p/ lancamentos
    execute format($p$create policy "%1$s_select" on public.%1$s for select
      using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())$p$, t);
    execute format($p$create policy "%1$s_insert" on public.%1$s for insert
      with check (workspace_id = public.meu_workspace_id())$p$, t);
    execute format($p$create policy "%1$s_update" on public.%1$s for update
      using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())$p$, t);
    execute format($p$create policy "%1$s_delete" on public.%1$s for delete
      using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())$p$, t);
  end loop;
end $$;

-- ─── 3. METAS / CATEGORIAS — leitura aberta, escrita só ADMIN ────────
-- NÃO mexer em `config`: ele guarda nome da oficina, lista de serviços,
-- capacidade e a sequência de notas — lido por todos os roles e ESCRITO
-- em fluxo operacional (emissão de recibo). Restringi-lo quebraria a UI.
-- metas (dashboard) e categorias (FinControl) podem ser lidas por todos,
-- mas só ADMIN altera.
do $$
declare t text;
begin
  foreach t in array array['metas','categorias_financeiras'] loop
    execute format('drop policy if exists %I on public.%I', t||'_all', t);
    execute format('drop policy if exists %I on public.%I', 'cats_all', t);   -- nome antigo (categorias)
    execute format('drop policy if exists %I on public.%I', 'metas_all', t);  -- nome antigo (metas)
    execute format($p$create policy "%1$s_select" on public.%1$s for select
      using (workspace_id = public.meu_workspace_id())$p$, t);
    execute format($p$create policy "%1$s_write" on public.%1$s for all
      using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
      with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro())$p$, t);
  end loop;
end $$;

-- ─── 4. AUDITORIA — leitura só ADMIN (insert continua aberto) ────────
drop policy if exists "audit_select" on public.auditoria;
create policy "audit_select" on public.auditoria for select
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro());

-- ─── 5. COLABORADORES — split de remuneração ─────────────────────────
-- 5.1 Nova tabela (colunas com os MESMOS nomes que o cliente usa)
create table if not exists public.colaboradores_remuneracao (
  colaborador_id uuid primary key references public.colaboradores(id) on delete cascade,
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  salario        numeric(12,2) not null default 0,
  comissao       numeric(5,2)  not null default 0,
  cpf            text,
  banco          text,
  tipo_conta     text,
  agencia        text,
  conta_bancaria text,
  pix_tipo       text
);
alter table public.colaboradores_remuneracao enable row level security;
drop policy if exists "remun_admin" on public.colaboradores_remuneracao;
create policy "remun_admin" on public.colaboradores_remuneracao for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create index if not exists idx_remun_ws on public.colaboradores_remuneracao(workspace_id);

-- 5.2 Helper: retorna o identificador da coluna se ela existir, senão um fallback
create or replace function public._src_col(p_col text, p_fallback text default 'null')
  returns text language sql stable as $$
  select case when exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='colaboradores' and column_name=p_col
  ) then quote_ident(p_col) else p_fallback end
$$;

-- 5.3 Copiar dados existentes (antes de dropar). Lida com comissao | comissao_pct.
do $$
declare
  v_com text;
begin
  v_com := case
    when public._src_col('comissao','#') <> '#'      then 'comissao'
    when public._src_col('comissao_pct','#') <> '#'  then 'comissao_pct'
    else '0' end;

  execute format($f$
    insert into public.colaboradores_remuneracao
      (colaborador_id, workspace_id, salario, comissao, cpf, banco, tipo_conta, agencia, conta_bancaria, pix_tipo)
    select id, workspace_id,
           coalesce((%s)::numeric, 0), coalesce((%s)::numeric, 0),
           %s, %s, %s, %s, %s, %s
    from public.colaboradores
    on conflict (colaborador_id) do nothing
  $f$,
    public._src_col('salario','0'), v_com,
    public._src_col('cpf'), public._src_col('banco'), public._src_col('tipo_conta'),
    public._src_col('agencia'), public._src_col('conta_bancaria'), public._src_col('pix_tipo')
  );
end $$;

-- 5.4 Dropar as colunas sensíveis de colaboradores (só as que existem)
do $$
declare c text;
begin
  foreach c in array array['salario','comissao','comissao_pct','cpf',
                           'banco','tipo_conta','agencia','conta_bancaria','pix_tipo'] loop
    if exists(select 1 from information_schema.columns
              where table_schema='public' and table_name='colaboradores' and column_name=c) then
      execute format('alter table public.colaboradores drop column %I', c);
    end if;
  end loop;
end $$;

drop function if exists public._src_col(text, text);

-- 5.5 Policies de colaboradores: SELECT p/ todos (nome do responsável nas OS),
--     escrita só GESTÃO (dono/socio/gerente).
drop policy if exists "colab_all" on public.colaboradores;
drop policy if exists "colab_select" on public.colaboradores;
drop policy if exists "colab_write" on public.colaboradores;
create policy "colab_select" on public.colaboradores for select
  using (workspace_id = public.meu_workspace_id());
create policy "colab_write" on public.colaboradores for all
  using (workspace_id = public.meu_workspace_id() and public.tem_gestao())
  with check (workspace_id = public.meu_workspace_id() and public.tem_gestao());
