-- =====================================================================
-- Migration: Financeiro #3 — receita de OS via RPC + INSERT restrito
-- Data: 2026-06-05
-- Base: supabase/AUDITORIA-SEGURANCA-2026-06-05.md (achado #3)
--
-- Problema: a policy de INSERT de `lancamentos` era aberta a qualquer
-- membro. Um não-admin (gerente/assistente) podia inserir, via API,
-- RECEITAS arbitrárias no livro-caixa (valores/categorias falsos) — que
-- ele nem consegue ler de volta. Vetor de fraude intra-oficina.
--
-- Correção:
--   (A) RPC `registrar_receita_os` (SECURITY DEFINER): a única porta para
--       um não-admin lançar RECEITA. Ela amarra o lançamento a uma OS real
--       do próprio workspace, força tipo='entrada' e a categoria de serviço
--       no servidor, carimba o autor e é idempotente (1 receita por OS).
--   (B) Policy de INSERT de `lancamentos`: admin (tem_financeiro) insere
--       qualquer coisa; não-admin só pode inserir DESPESA (tipo='saida',
--       p.ex. compra de material no Estoque). RECEITA direta fica bloqueada
--       — tem de passar pela RPC.
--
-- Depende de: lancamentos.origem/forma/meta (fincontrol-fase1) e
-- tem_financeiro() (20260530_rls-por-role). Não-destrutiva.
-- pagamentos/parcelas NÃO são alterados aqui (ver nota de fase 2 no PR).
-- =====================================================================

-- ─── (A) RPC: receita de OS ──────────────────────────────────────────
create or replace function public.registrar_receita_os(
  p_veiculo_id uuid,
  p_valor      numeric,
  p_forma      text default null,
  p_obs        text default null,
  p_data       date default current_date
) returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_ws      uuid;
  v_modelo  text;
  v_placa   text;
  v_cat     text;
  v_desc    text;
  v_lanc_id uuid;
begin
  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor inválido para receita de OS';
  end if;

  -- A OS precisa existir e pertencer ao workspace do chamador.
  select workspace_id, modelo, placa
    into v_ws, v_modelo, v_placa
    from public.veiculos
   where id = p_veiculo_id;

  if v_ws is null then
    raise exception 'OS não encontrada';
  end if;
  if v_ws is distinct from public.meu_workspace_id() then
    raise exception 'OS pertence a outro workspace';
  end if;

  -- Categoria de serviço configurada no workspace (forçada no servidor).
  select coalesce(cat_servico, 'Serviços') into v_cat
    from public.config where workspace_id = v_ws;
  v_cat := coalesce(v_cat, 'Serviços');

  v_desc := 'Serviço — ' || coalesce(v_modelo, '') ||
            ' (' || coalesce(v_placa, '') || ')';

  -- Idempotência: uma receita-de-OS (origem='oficina') por veículo.
  select id into v_lanc_id
    from public.lancamentos
   where workspace_id = v_ws
     and veiculo_id   = p_veiculo_id
     and tipo = 'entrada'
     and origem = 'oficina'
   limit 1;
  if v_lanc_id is not null then
    return v_lanc_id;  -- já lançada; não duplica
  end if;

  insert into public.lancamentos(
    workspace_id, tipo, descricao, valor, categoria, data,
    forma, obs, veiculo_id, origem, meta
  ) values (
    v_ws, 'entrada', v_desc, p_valor, v_cat, coalesce(p_data, current_date),
    p_forma, p_obs, p_veiculo_id, 'oficina',
    jsonb_build_object('autor', auth.uid())
  )
  returning id into v_lanc_id;

  return v_lanc_id;
end;
$$;

-- ─── (B) INSERT de lancamentos: receita direta só p/ admin ───────────
-- Recria a policy de INSERT criada em 20260530_rls-por-role.sql.
drop policy if exists "lancamentos_insert" on public.lancamentos;
create policy "lancamentos_insert" on public.lancamentos for insert
  with check (
    workspace_id = public.meu_workspace_id()
    and (
      public.tem_financeiro()   -- admin (dono/socio): qualquer lançamento
      or tipo = 'saida'         -- não-admin: só DESPESA (ex.: compra de material)
    )
  );

-- ─── Verificação (rodar após aplicar) ────────────────────────────────
-- 1) Como NÃO-admin, inserir uma receita direta deve FALHAR:
--    insert into lancamentos(workspace_id,tipo,descricao,valor)
--    values (public.meu_workspace_id(),'entrada','x',1);   -- 42501 esperado
-- 2) A RPC deve lançar a receita amarrada à OS:
--    select public.registrar_receita_os('<veiculo_id>', 1234.50, 'PIX', null);
