-- =====================================================================
-- Migration: Financeiro #3 — fase 2 (pagamentos e parcelas)
-- Data: 2026-06-07
-- Base: supabase/AUDITORIA-SEGURANCA-2026-06-05.md (achado #3, fase 2)
--
-- Completa o #3 fechando o INSERT direto em `pagamentos` e `parcelas`,
-- que ainda eram graváveis por qualquer membro.
--
-- Mapa dos fluxos (do código):
--   • pagamentos: só são inseridos no fluxo de SALÁRIO (painel dono/socio).
--     => INSERT direto restrito a admin (tem_financeiro). Sem mudança no front.
--   • parcelas: criadas no botão "Parcelar" dentro do modal de SAÍDA, acessível
--     a não-admin (gerente/assistente). Por isso, em vez de só restringir,
--     adicionamos a RPC `registrar_parcela_os` (SECURITY DEFINER), amarrada a
--     uma OS real do workspace, e restringimos o INSERT direto a admin.
--
-- Depende de tem_financeiro() (20260530_rls-por-role). Não-destrutiva.
-- =====================================================================

-- ─── PAGAMENTOS — INSERT direto só admin ─────────────────────────────
drop policy if exists "pagamentos_insert" on public.pagamentos;
create policy "pagamentos_insert" on public.pagamentos for insert
  with check (
    workspace_id = public.meu_workspace_id()
    and public.tem_financeiro()
  );

-- ─── PARCELAS — RPC amarrada à OS ────────────────────────────────────
create or replace function public.registrar_parcela_os(
  p_veiculo_id uuid,
  p_descricao  text,
  p_valor      numeric,
  p_vencimento date
) returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_ws      uuid;
  v_parc_id uuid;
begin
  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor inválido para parcela';
  end if;
  if p_vencimento is null then
    raise exception 'Vencimento obrigatório';
  end if;
  if p_veiculo_id is null then
    raise exception 'Parcela deve referenciar uma OS';
  end if;

  -- A OS precisa existir e pertencer ao workspace do chamador.
  select workspace_id into v_ws from public.veiculos where id = p_veiculo_id;
  if v_ws is null then
    raise exception 'OS não encontrada';
  end if;
  if v_ws is distinct from public.meu_workspace_id() then
    raise exception 'OS pertence a outro workspace';
  end if;

  insert into public.parcelas(
    workspace_id, veiculo_id, descricao, valor, vencimento, pago
  ) values (
    v_ws, p_veiculo_id, p_descricao, p_valor, p_vencimento, false
  )
  returning id into v_parc_id;

  return v_parc_id;
end;
$$;

-- ─── PARCELAS — INSERT direto só admin (não-admin usa a RPC) ──────────
drop policy if exists "parcelas_insert" on public.parcelas;
create policy "parcelas_insert" on public.parcelas for insert
  with check (
    workspace_id = public.meu_workspace_id()
    and public.tem_financeiro()
  );

-- ─── Verificação (rodar após aplicar) ────────────────────────────────
-- Como NÃO-admin:
--   insert into pagamentos(workspace_id,tipo,descricao,valor)
--     values (public.meu_workspace_id(),'saida','x',1);          -- 42501
--   insert into parcelas(workspace_id,valor,vencimento)
--     values (public.meu_workspace_id(),1,current_date);         -- 42501
--   select public.registrar_parcela_os('<veiculo_id>','1/3',100, current_date); -- ok
