-- =====================================================================
-- Migration: Correções de segurança — modelo de acesso (RLS / papéis)
-- Data: 2026-06-05
-- Base: supabase/AUDITORIA-SEGURANCA-2026-06-05.md
--
-- Corrige:
--   #1 (CRÍTICO) adicionar_membro() exposta via RPC -> escalonamento p/ dono
--                e acesso a outro workspace. Fecha o EXECUTE p/ anon/authenticated.
--   #2 (MÉDIO)   criar_workspace() aceitava p_user_id arbitrário.
--   #4 (BAIXO)   profiles_insert validava só workspace_id, não o papel.
--
-- NÃO destrutiva. Aplicar pelo SQL Editor (mesmo fluxo das migrations anteriores).
-- A cadeia legítima de convite (resgatar_convite -> adicionar_membro) continua
-- funcionando: resgatar_convite é SECURITY DEFINER e executa como o dono da
-- função, então o REVOKE não a afeta. O webhook on-signup usa a service role,
-- que ignora os checks de auth.uid() abaixo.
-- =====================================================================

-- ─── #1 — Fechar adicionar_membro() para chamadas diretas via RPC ────
-- Só a cadeia interna (resgatar_convite) e a service role devem chamá-la.
revoke execute on function public.adicionar_membro(uuid, uuid, text, text, text)
  from public, anon, authenticated;

-- ─── #2 — criar_workspace() deve amarrar o profile ao próprio usuário ─
-- Recriada com guarda: quando há usuário autenticado (chamada do cliente),
-- p_user_id precisa ser o próprio auth.uid(). A service role (auth.uid() null,
-- usada pelo on-signup) passa direto.
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
  if auth.uid() is not null and p_user_id is distinct from auth.uid() then
    raise exception 'p_user_id deve ser o usuário autenticado';
  end if;

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

-- ─── #4 — profiles_insert: só o próprio usuário ou dono/socio ─────────
-- meu_role() existe desde 20260530_correcoes-rapidas.sql.
drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles
  for insert with check (
    workspace_id = public.meu_workspace_id()
    and (id = auth.uid() or public.meu_role() in ('dono','socio'))
  );

-- ─── Verificação (rode após aplicar; esperado: authenticated_pode = false) ─
-- select p.proname,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_pode,
--        has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_pode
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname='public' and p.proname='adicionar_membro';
