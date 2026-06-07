# Deploy — Financeiro #3 fase 2: pagamentos e parcelas (2026-06-07)

Completa o achado #3 da auditoria, fechando o INSERT direto em `pagamentos`
e `parcelas`. Migration: **`20260607_financeiro-fase2-pagamentos-parcelas.sql`**
+ mudança no `index.html` (parcelas via RPC).

> ⚠️ Mexe em fluxo de dinheiro. Aplique o SQL e teste no app antes de concluir.
> Recomendado validar com usuários de teste de cada papel.

## Ordem
1. **SQL** — rode `20260607_financeiro-fase2-pagamentos-parcelas.sql` no SQL Editor.
2. **Frontend** — publique o `index.html`. **SQL primeiro**: se o front novo subir
   antes, a RPC `registrar_parcela_os` não existe e o parcelamento na saída falha.

## O que muda
- **pagamentos**: INSERT direto só admin (`tem_financeiro`). Sem mudança de UI —
  hoje só o fluxo de **salário** (painel dono/socio) insere pagamento.
- **parcelas**: INSERT direto só admin; o **parcelamento na saída** (gerente/
  assistente) passa a usar a RPC `registrar_parcela_os`, amarrada a uma OS real.

## Validação pós-deploy

### A) SQL / console como NÃO-admin (gerente)
```js
(await db.from('pagamentos').insert({workspace_id: wsId(), tipo:'saida',
   descricao:'x', valor:1})).error                      // != null (42501)
(await db.from('parcelas').insert({workspace_id: wsId(),
   valor:1, vencimento:'2026-06-30'})).error            // != null (42501)
```

### B) App — fluxos que DEVEM continuar funcionando
- **Parcelar** na tela de saída (gerente/assistente): cria as N parcelas sem erro
  e elas aparecem nas contas a receber.
- **Folha de salários** (dono/socio): registra pagamento + lançamento normalmente.
- **Marcar parcela como paga** (FinControl, admin): continua OK.

## Rollback
```sql
-- pagamentos: volta INSERT aberto a qualquer membro
drop policy if exists "pagamentos_insert" on public.pagamentos;
create policy "pagamentos_insert" on public.pagamentos for insert
  with check (workspace_id = public.meu_workspace_id());
-- parcelas: idem
drop policy if exists "parcelas_insert" on public.parcelas;
create policy "parcelas_insert" on public.parcelas for insert
  with check (workspace_id = public.meu_workspace_id());
-- e republicar o index.html anterior (parcelas voltam ao INSERT direto).
-- a função registrar_parcela_os pode ficar; não atrapalha.
```

## Checklist
- [ ] SQL aplicado
- [ ] `index.html` publicado
- [ ] Validação A (insert direto não-admin falha em pagamentos e parcelas)
- [ ] Validação B (parcelar na saída, salário e marcar paga continuam OK)
