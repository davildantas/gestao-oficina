# Deploy — Financeiro #3: receita de OS via RPC (2026-06-05)

Fecha o vetor de **receita falsa por não-admin** (achado #3 da auditoria).
Migration: **`supabase/migrations/20260605_financeiro-receita-os.sql`** +
mudança no `index.html` (fluxo de saída usa a RPC).

> ⚠️ Mexe em **fluxo de dinheiro**. Aplique o SQL e teste no app **antes** de
> considerar concluído. Recomendado validar primeiro com usuários de teste de
> cada papel.

## Ordem
1. **SQL** — rode `20260605_financeiro-receita-os.sql` no SQL Editor.
   - Cria a RPC `registrar_receita_os` e recria a policy `lancamentos_insert`.
2. **Frontend** — publique o `index.html` (o fluxo de saída passa a chamar a RPC).
   - Pode subir junto com o SQL. Se o front novo subir **antes** do SQL, a RPC
     não existe e o lançamento de receita na saída falha (a saída em si é salva;
     só o lançamento no FinControl erra). Por isso: **SQL primeiro**.

## O que muda no comportamento
- Lançar **receita** (entrada) por **não-admin** só acontece via a RPC, amarrada
  a uma OS real, com categoria de serviço e autor definidos no servidor.
- Lançar **despesa** (saida — ex.: compra de material no Estoque) por não-admin
  continua igual (a policy permite `tipo='saida'`).
- Admin (dono/socio) continua inserindo qualquer lançamento direto.

## Validação pós-deploy

### A) SQL — a receita direta por não-admin deve falhar
Logado/representando um **gerente** (não-admin), no SQL Editor com o papel
`authenticated` simulado **ou** no app (console):
```js
// como NÃO-admin — deve retornar erro (42501):
(await db.from('lancamentos').insert({workspace_id: wsId(), tipo:'entrada',
   descricao:'teste', valor:1}).select()).error   // != null  (bloqueado)

// despesa por não-admin continua permitida:
(await db.from('lancamentos').insert({workspace_id: wsId(), tipo:'saida',
   descricao:'teste despesa', valor:1})).error     // null
```

### B) App — fluxos que DEVEM continuar funcionando
- **Registrar saída** com valor e forma ≠ "A receber", com `autoReceita` ligado:
  a receita aparece no FinControl (para o dono) e **não duplica** se a saída for
  reprocessada (idempotência por OS).
- **Compra de material** no Estoque (lança despesa) — por gerente/assistente.
- **Salários, seguradora, FinControl manual** — por dono/socio.

### C) Idempotência
Registrar saída do mesmo veículo duas vezes deve gerar **uma** receita só
(a RPC retorna o lançamento existente).

## Fora de escopo (fase 2, ver PR)
`pagamentos` e `parcelas` continuam com INSERT por qualquer membro. Travá-los
exige verificar caso a caso quem cria parcelas/pagamentos no fluxo real —
proposta separada para não arriscar regressão no caixa agora.

## Rollback
```sql
-- volta a policy antiga (INSERT aberto a qualquer membro):
drop policy if exists "lancamentos_insert" on public.lancamentos;
create policy "lancamentos_insert" on public.lancamentos for insert
  with check (workspace_id = public.meu_workspace_id());
-- e republicar o index.html anterior (saída volta ao INSERT direto).
-- a função registrar_receita_os pode ficar; não atrapalha.
```

## Checklist
- [ ] SQL aplicado
- [ ] `index.html` publicado
- [ ] Validação A (receita direta não-admin falha; despesa ok)
- [ ] Validação B (saída lança receita p/ dono; estoque/salário/seguradora ok)
- [ ] Validação C (sem duplicar receita)
