-- =====================================================================
-- Migration: Correções rápidas (segurança + integridade + realtime)
-- Data: 2026-05-30
-- Inclui:
--   (1) profiles_update — impedir auto-promoção de role
--   (7) orcamentos.numero — numeração atômica no banco (anti-corrida)
--   (6) Realtime — publicar tabelas faltantes (clientes, parcelas, lancamentos)
-- =====================================================================

-- ---------------------------------------------------------------------
-- (1) SEGURANÇA — profiles_update
-- A policy antiga só checava workspace_id, permitindo que qualquer membro
-- alterasse o próprio role (ex.: operador -> dono). Agora:
--   • o WITH CHECK exige que o registro continue no mesmo workspace;
--   • a troca de `role` só é permitida para dono/socio (via função helper).
-- ---------------------------------------------------------------------
create or replace function public.meu_role()
returns text language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles
  for update
  using (workspace_id = public.meu_workspace_id())
  with check (
    workspace_id = public.meu_workspace_id()
    and (
      -- mantém o mesmo role (edição de dados pessoais por qualquer membro)
      role = (select p.role from public.profiles p where p.id = profiles.id)
      -- ou quem está alterando é dono/socio (pode promover/rebaixar)
      or public.meu_role() in ('dono','socio')
    )
  );

-- ---------------------------------------------------------------------
-- (7) ORÇAMENTOS — numeração atômica por workspace
-- Substitui o gerarNumero() do cliente (Math.max+1), que sofre corrida
-- quando dois usuários criam orçamentos simultaneamente.
-- ---------------------------------------------------------------------
create or replace function public.set_orcamento_numero()
returns trigger language plpgsql as $$
begin
  if new.numero is null or new.numero = 0 then
    -- lock por workspace; liberado no fim da transação
    perform pg_advisory_xact_lock(hashtext(new.workspace_id::text));
    select coalesce(max(numero), 1000000) + 1
      into new.numero
      from public.orcamentos
     where workspace_id = new.workspace_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orc_numero on public.orcamentos;
create trigger trg_orc_numero
  before insert on public.orcamentos
  for each row execute function public.set_orcamento_numero();

-- numero passa a ser opcional no insert (o trigger preenche)
alter table public.orcamentos alter column numero drop not null;

-- ---------------------------------------------------------------------
-- (6) REALTIME — publicar tabelas que o app passou a sincronizar
-- Sem isto, a inscrição no cliente não recebe eventos dessas tabelas.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['clientes','parcelas','lancamentos'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null; -- já publicada
    end;
  end loop;
end $$;
