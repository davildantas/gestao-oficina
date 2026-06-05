# Deploy — Correções de segurança RLS/papéis (2026-06-05)

Aplica os achados #1, #2 e #4 da `AUDITORIA-SEGURANCA-2026-06-05.md`.
Migration: **`supabase/migrations/20260605_seguranca-rls.sql`**. Não-destrutiva.

## Aplicar (SQL Editor)
Rode o arquivo inteiro de uma vez. Ele:
1. **#1** `revoke execute` em `adicionar_membro` para `anon/authenticated/public`.
2. **#2** recria `criar_workspace` com guarda `p_user_id = auth.uid()`.
3. **#4** recria `profiles_insert` (só o próprio usuário ou dono/socio).

## Validação pós-deploy
```sql
-- #1: deve vir authenticated_pode = false e anon_pode = false
select has_function_privilege('authenticated',
         'public.adicionar_membro(uuid,uuid,text,text,text)', 'EXECUTE') as authenticated_pode,
       has_function_privilege('anon',
         'public.adicionar_membro(uuid,uuid,text,text,text)', 'EXECUTE') as anon_pode;
```
No app (console do navegador, logado como usuário comum):
```js
// deve FALHAR (permission denied for function adicionar_membro):
(await db.rpc('adicionar_membro', {p_user_id: DB.session.id,
   p_workspace_id: wsId(), p_nome:'x', p_username:'x', p_role:'dono'})).error  // != null
```

## Regressão a conferir (deve continuar funcionando)
- **Auto-cadastro** (novo usuário cria a própria oficina) — usa a service role
  no `on-signup`, que ignora a guarda do #2.
- **Convite:** dono gera código (`gerar_convite`) e novo usuário resgata
  (`resgatar_convite`) — a cadeia chama `adicionar_membro` internamente como
  dono da função, então o revoke do #1 não a afeta.

## Rollback
```sql
grant execute on function public.adicionar_membro(uuid,uuid,text,text,text)
  to authenticated;            -- reabre (NÃO recomendado: reintroduz o furo #1)
-- #2/#4: recriar as versões antigas do schema.sql original, se necessário.
```

## Checklist
- [ ] `20260605_seguranca-rls.sql` aplicada
- [ ] Validação #1 (authenticated_pode = false) ok
- [ ] RPC direta de `adicionar_membro` falha no app
- [ ] Auto-cadastro e fluxo de convite continuam OK
