# Auditoria de Segurança — Oficina Manager (2026-06-05)

Revisão focada no **modelo de acesso** do sistema (multi-tenant por
`workspace`, RLS no Postgres, papéis dono/socio/gerente/assistente/operador).
Base analisada: `supabase/schema.sql`, `supabase/migrations/*.sql`,
`supabase/convites-migration.sql`, `supabase/functions/on-signup/` e as
chamadas RPC em `index.html`.

> ⚠️ Este é um **relatório** — nenhuma correção foi aplicada. As correções
> sugeridas (SQL) estão no fim de cada achado para você aplicar pelo SQL Editor
> depois de validar. Itens marcados **[confirmar em produção]** dependem dos
> grants reais do banco, que não consigo inspecionar a partir do repositório.

---

## Resumo executivo

| # | Severidade | Achado | Risco |
|---|-----------|--------|-------|
| 1 | **CRÍTICA** | `adicionar_membro()` é `SECURITY DEFINER` sem checagem de quem chama e (aparentemente) sem `REVOKE EXECUTE` | Escalonamento de privilégio para `dono` e acesso a **outro workspace** (vazamento entre clientes) |
| 2 | **MÉDIA** | `criar_workspace()` aceita `p_user_id` arbitrário, sem exigir `= auth.uid()` | Criar workspace/atribuir "dono" em nome de outro usuário |
| 3 | **MÉDIA** | INSERT financeiro aberto a qualquer membro (`lancamentos`, `pagamentos`, `parcelas`) | Poluição do livro-caixa por não-admin (entradas/saídas falsas) |
| 4 | **BAIXA** | `profiles_insert` valida só `workspace_id`, não o papel | Inserir perfis de terceiros dentro do próprio workspace |
| 5 | **INFO** | Verificar grants de função e RLS no Realtime | Defesa em profundidade |

O achado **#1 é o que pode "comprometer o sistema"** de fato — priorize-o.

---

## 1. CRÍTICA — `adicionar_membro()` permite escalonamento e invasão entre workspaces

**Onde:** `supabase/schema.sql:439-457`

```sql
create or replace function public.adicionar_membro(
  p_user_id uuid, p_workspace_id uuid, p_nome text, p_username text,
  p_role text default 'operador'
) returns void language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, workspace_id, nome, username, role)
  values (p_user_id, p_workspace_id, p_nome, p_username, p_role)
  on conflict (id) do update
    set workspace_id = excluded.workspace_id,
        nome = excluded.nome, username = excluded.username,
        role = excluded.role;
end;
$$;
```

**Por que é grave:**
- A função roda como **`SECURITY DEFINER`** (privilégios do dono/superuser),
  então **ignora o RLS** e o `check` da policy `profiles_update` que justamente
  foi criada para impedir auto-promoção (migration `20260530_correcoes-rapidas.sql`).
- Ela **não verifica quem está chamando** — aceita qualquer `p_user_id`,
  `p_workspace_id` e `p_role`, e faz **upsert** (`on conflict do update`).
- Não há nenhum `revoke execute ... from authenticated/anon/public` no
  repositório. No Supabase, funções do schema `public` ficam **executáveis via
  PostgREST RPC** pelos papéis `anon`/`authenticated` por padrão. **[confirmar em produção]**
- **Evidência de que RPCs assim estão expostas:** o próprio front chama
  `db.rpc('criar_workspace', …)` em `index.html:139` com a chave anônima —
  ou seja, o padrão de grants está ativo e `adicionar_membro` (mesmo schema,
  mesmos grants) é alcançável da mesma forma.

**Cenário de exploração (usuário autenticado comum — ex.: um "operador"):**
```js
// no console do navegador, logado como operador:
await db.rpc('adicionar_membro', {
  p_user_id: SEU_AUTH_UID,          // o próprio id
  p_workspace_id: SEU_WORKSPACE,    // o próprio workspace
  p_nome:'x', p_username:'x',
  p_role:'dono'                     // vira DONO
});
```
Resultado: o operador vira `dono` e passa a ler/editar **todo o financeiro**
(`lancamentos`, `pagamentos`, salários em `colaboradores_remuneracao`),
apagar o livro-caixa, etc. Trocando `p_workspace_id` por **outro** workspace,
ele **migra a própria conta para a oficina da concorrência** e passa a enxergar
todos os dados daquele tenant (o RLS libera tudo com base em
`profiles.workspace_id`, que ele acabou de sobrescrever).

> Observação: invadir *outro* workspace exige conhecer o UUID dele (não trivial
> de adivinhar). Mas a **auto-promoção a `dono` no próprio workspace não exige
> nenhum dado externo** — já é, por si só, um furo crítico no modelo de papéis.

**Correção recomendada** (a cadeia legítima `resgatar_convite` → `adicionar_membro`
continua funcionando, porque `resgatar_convite` também é `SECURITY DEFINER` e
executa como dono, então o `revoke` não a afeta):
```sql
revoke execute on function public.adicionar_membro(uuid,uuid,text,text,text)
  from public, anon, authenticated;

-- defesa extra: a própria função recusar atribuição de 'dono' por convite
-- e exigir que o convite seja a única porta (opcional, já que o revoke basta).
```

---

## 2. MÉDIA — `criar_workspace()` aceita `p_user_id` arbitrário

**Onde:** `supabase/schema.sql:409-433` · chamada exposta em `index.html:139`

A função cria um workspace e insere um `profile` **dono** para o `p_user_id`
recebido, sem exigir `p_user_id = auth.uid()`. Como é chamada direto do cliente,
um usuário autenticado pode invocá-la com o `p_user_id` de **outra pessoa**.

**Impacto:** limitado pela PK de `profiles` (se o alvo já tem profile, dá
conflito e erra), mas permite criar workspaces espúrios e atribuir "dono" a um
usuário recém-criado que ainda não tenha profile. Menos grave que o #1, porém é
a mesma classe de problema (função privilegiada sem amarrar ao chamador).

**Correção recomendada:**
```sql
-- dentro de criar_workspace, no início do corpo:
if p_user_id is distinct from auth.uid() then
  raise exception 'p_user_id deve ser o usuário autenticado';
end if;
```
(O `on-signup` usa a **service role**, que ignora esse check — então o
auto-cadastro via webhook continua funcionando.)

---

## 3. MÉDIA — INSERT financeiro aberto a qualquer membro

**Onde:** `supabase/migrations/20260530_rls-por-role.sql:23-41`

As policies de `lancamentos`, `pagamentos` e `parcelas` são **assimétricas**:
SELECT/UPDATE/DELETE exigem `tem_financeiro()` (dono/socio), mas o **INSERT** só
checa `workspace_id`:
```sql
create policy "..._insert" on public.<tbl> for insert
  with check (workspace_id = public.meu_workspace_id());   -- sem papel!
```

**Impacto:** qualquer membro autenticado (gerente, assistente, operador) pode
**inserir** entradas/saídas arbitrárias no livro-caixa — valores falsos,
"saídas" infladas, parcelas fantasma. Ele não consegue **ler** de volta (o
SELECT é admin-only), mas consegue **poluir/fraudar** os números que o dono vê.

Isto é um **trade-off documentado** no código (fluxos operacionais geram
receita/despesa automática). Mantê-lo é uma decisão de negócio, mas registre o
risco. Para fechar de verdade sem quebrar os fluxos, a recomendação é mover a
escrita financeira para uma **RPC `SECURITY DEFINER`** que valida o contexto
(ex.: só insere "receita de serviço" vinculada a uma OS real do workspace) e
revogar o INSERT direto:
```sql
-- esboço:
-- revoke insert nas 3 tabelas; criar registrar_receita_os()/registrar_saida()
-- security definer que valida veiculo_id ∈ workspace e categoria permitida.
```

---

## 4. BAIXA — `profiles_insert` não verifica papel

**Onde:** `supabase/schema.sql:315-316`

```sql
create policy "profiles_insert" on public.profiles
  for insert with check (workspace_id = public.meu_workspace_id());
```
Permite a um membro inserir linhas em `profiles` para **outros** `auth.uid`
dentro do próprio workspace, com qualquer `role`. Fica praticamente neutralizado
se o #1 for corrigido (a porta principal é `adicionar_membro`), mas convém
restringir a criação de perfis a gestão/dono ou apenas ao próprio usuário:
```sql
drop policy "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for insert
  with check (
    workspace_id = public.meu_workspace_id()
    and (id = auth.uid() or public.meu_role() in ('dono','socio'))
  );
```

---

## 5. INFO — verificações de defesa em profundidade [confirmar em produção]

- **Grants de função:** liste o que está exposto via RPC e confirme o #1/#2:
  ```sql
  select p.proname, p.prosecdef as security_definer,
         coalesce(has_function_privilege('authenticated', p.oid, 'EXECUTE'),false) as authenticated_pode,
         coalesce(has_function_privilege('anon',          p.oid, 'EXECUTE'),false) as anon_pode
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname in ('adicionar_membro','criar_workspace','gerar_convite',
                       'resgatar_convite','movimentar_estoque');
  ```
  Esperado após a correção: `adicionar_membro` com `authenticated_pode = false`.
- **RLS no Realtime:** `pagamentos` está publicado em `supabase_realtime`
  (`schema.sql:479`). Confirme que o Realtime respeita o SELECT admin-only
  (assinantes não-admin não devem receber eventos de `pagamentos`).
- **`search_path`** das funções `SECURITY DEFINER`: as auditadas já fixam
  `set search_path = public` ✅ (boa prática contra hijack de schema).
- **Chave anônima no `index.html`:** normal e esperado no Supabase (protegida
  por RLS). **Não** é um vazamento — desde que o RLS esteja correto (ver #1).

---

## Prioridade sugerida
1. **Aplicar a correção do #1** (revoke) — fecha o furo crítico, baixo risco de
   regressão (a cadeia de convite não usa o grant direto).
2. Rodar o SQL de verificação do #5 e confirmar `adicionar_membro` fechada.
3. Endereçar #2 e #4 (hardening barato).
4. Decidir o trade-off do #3 (negócio vs. integridade do caixa).

> Nada aqui altera o app/`index.html`. As mudanças de Kanban do PR #19 **não
> introduzem** nenhum destes itens — os achados #1–#4 são **pré-existentes** no
> modelo de acesso e independem daquele PR.
