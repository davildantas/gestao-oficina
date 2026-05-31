# Proposta — RLS por Role (controle de acesso no banco)

**Problema:** hoje o RLS isola por `workspace_id`, mas **não por role**. As restrições de
papel existem só no cliente (`data-role` no menu + `hasRole()`). Qualquer membro
autenticado pode, via console/anon key, ler salários, financeiro e auditoria, e
escrever em qualquer tabela. Esta proposta move o controle de papel para o banco.

**Decisões tomadas (2026-05-30):**
- Salário/comissão/dados bancários/CPF → **tabela separada** restrita a dono/sócio.
- Restringir **leitura e escrita** (não só leitura).

---

## 1. Camadas de papel (tiers)

| Tier | Roles | Acesso |
|---|---|---|
| **ADMIN** | `dono`, `socio` | Tudo: operacional + financeiro + RH + config + auditoria |
| **GESTÃO** | `gerente` | Operacional + cadastro de colaboradores (sem remuneração/financeiro) |
| **OPERACIONAL** | `assistente`, `operador`, `colaborador` | Operacional (OS, clientes, estoque, agenda, orçamentos) |

### Helpers (funções `stable security definer`)
```sql
-- já criada na migration 20260530: public.meu_role()
create or replace function public.tem_financeiro() returns boolean
  language sql stable security definer set search_path = public
  as $$ select public.meu_role() in ('dono','socio') $$;

create or replace function public.tem_gestao() returns boolean
  language sql stable security definer set search_path = public
  as $$ select public.meu_role() in ('dono','socio','gerente') $$;
```

---

## 2. Classificação das tabelas

### A) Operacional — todos os membros (leitura + escrita, isolado por workspace)
`veiculos`, `orcamento_itens`, `orcamentos`, `orcamento_servicos`,
`orcamento_lancamentos`, `catalogo_servicos`, `clientes`, `agenda`, `estoque`,
`estoque_movimentacoes`, `materiais_os`, `fila`, `notas`, `satisfacoes`, `fotos`.

→ **Mantêm a policy atual** (`workspace_id = meu_workspace_id()`). Nenhuma mudança.

### B) Financeiro — leitura/edição só ADMIN, **mas inserção aberta**
`lancamentos`, `pagamentos`, `parcelas`.

⚠️ **Por que inserção aberta?** A saída de OS (auto-receita) e a baixa de material
criam `lancamentos` automaticamente, e quem faz isso é gerente/assistente. Bloquear
o INSERT quebraria o fluxo operacional. Solução: **policy assimétrica** — qualquer
membro pode *inserir* (gerar receita/despesa), mas só ADMIN pode *ver, editar e
apagar* o livro financeiro (que é o que a UI já reflete: Fluxo de Caixa / FinControl
são `dono,socio`).

```sql
-- exemplo para lancamentos (repetir p/ pagamentos e parcelas)
drop policy if exists "lanc_all" on public.lancamentos;
create policy "lanc_select" on public.lancamentos for select
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create policy "lanc_insert" on public.lancamentos for insert
  with check (workspace_id = public.meu_workspace_id());           -- aberto
create policy "lanc_update" on public.lancamentos for update
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
create policy "lanc_delete" on public.lancamentos for delete
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
```
> Alternativa mais estrita: rotear as inserções automáticas por uma RPC
> `security definer` e fechar o INSERT direto. Mais seguro, porém mais trabalho no
> cliente. A versão assimétrica acima é o melhor custo/benefício e cobre o vazamento
> real (leitura do ledger).

### C) Metas/Categorias — leitura aberta, escrita só ADMIN
`metas`, `categorias_financeiras`.
> **`config` NÃO é restrito:** guarda nome da oficina, lista de serviços,
> capacidade e a sequência de notas — lido por todos os roles e escrito em fluxo
> operacional (emissão de recibo). Restringi-lo quebraria a UI. Mantém `config_all`.
```sql
drop policy if exists "metas_all" on public.metas;
create policy "metas_admin" on public.metas for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
-- idem categorias_financeiras, config
```

### D) Auditoria — leitura só ADMIN, inserção aberta
```sql
drop policy if exists "audit_select" on public.auditoria;
create policy "audit_select" on public.auditoria for select
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro());
-- "audit_insert" permanece aberto (todos logam)
```

### E) Colaboradores — split de remuneração
Painel "Colaboradores" é `dono,socio,gerente`; o Kanban mostra o **nome** do
responsável (colaborador) para todos. Logo:

- **`colaboradores`** (nome, função, telefone, ativo, endereço básico):
  - SELECT: todos os membros (necessário p/ exibir responsável nas OS).
  - INSERT/UPDATE/DELETE: só GESTÃO.
- **`colaboradores_remuneracao`** (nova): `salario`, `comissao_pct`, `banco`,
  `tipo_conta`, `agencia`, `conta_bancaria`, `pix_tipo`, `cpf`, `rg`, `pis_pasep`,
  `ctps*`, etc. → ALL só ADMIN.

```sql
create table public.colaboradores_remuneracao (
  colaborador_id uuid primary key references public.colaboradores(id) on delete cascade,
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  salario        numeric(12,2) not null default 0,
  comissao_pct   numeric(5,2)  not null default 0,
  cpf text, rg text, pis_pasep text,
  banco text, tipo_conta text, agencia text, conta_bancaria text, pix_tipo text
  -- migrar demais colunas sensíveis de colaboradores conforme necessário
);
alter table public.colaboradores_remuneracao enable row level security;
create policy "remun_admin" on public.colaboradores_remuneracao for all
  using (workspace_id = public.meu_workspace_id() and public.tem_financeiro())
  with check (workspace_id = public.meu_workspace_id() and public.tem_financeiro());

-- colaboradores: SELECT aberto, escrita só gestão
drop policy if exists "colab_all" on public.colaboradores;
create policy "colab_select" on public.colaboradores for select
  using (workspace_id = public.meu_workspace_id());
create policy "colab_write" on public.colaboradores for all
  using (workspace_id = public.meu_workspace_id() and public.tem_gestao())
  with check (workspace_id = public.meu_workspace_id() and public.tem_gestao());
```
**Migração de dados:** copiar colunas sensíveis para a nova tabela e depois
`alter table colaboradores drop column salario, comissao_pct, ...`.

---

## 3. Matriz resumida

| Recurso | dono/socio | gerente | assistente/operador/colaborador |
|---|---|---|---|
| OS, clientes, estoque, agenda, orçamentos | RW | RW | RW |
| Colaboradores (cadastro) | RW | RW | R (nome) |
| Remuneração / dados bancários | RW | — | — |
| Lançamentos / pagamentos / parcelas | RW | inserir | inserir |
| Metas, categorias, config | RW | — | — |
| Auditoria | R | — | — |

---

## 4. Mudanças necessárias no cliente

1. **`carregarTudo`**: separar a carga de remuneração — só buscar
   `colaboradores_remuneracao` quando `hasRole('dono','socio')`; senão usar `[]`.
   Hoje `colaboradores.select('*')` traz salário; após o split, o gerente recebe o
   colaborador sem os números (e a UI já esconde a aba).
2. **Salvar colaborador**: gravar campos sensíveis via upsert na nova tabela
   (só dono/socio). Os demais campos seguem em `colaboradores`.
3. **Tela de Salários / FinControl**: já restritas por `hasRole` — nenhuma mudança
   funcional, mas agora protegidas mesmo se alguém burlar o cliente.
4. **Tratamento de erro 42501** (`Sem permissão`): o `traduzirErro` já cobre.

---

## 5. Rollout seguro (ordem importa)

1. Aplicar helpers (`tem_financeiro`, `tem_gestao`) — inócuo.
2. Criar `colaboradores_remuneracao` + migrar dados + ajustar cliente (carga/salvar).
3. **Só então** trocar as policies (B, C, D, E). Trocar antes de ajustar o cliente
   faz o gerente perder leitura de salário no meio da sessão (esperado), mas pode
   gerar toasts de erro até o deploy do front.
4. Testar com um usuário de cada role (criar via convite com role específico) e
   validar no console: `await db.from('lancamentos').select('*')` deve falhar para
   operacional e funcionar para dono.

### Riscos
- A inserção aberta em B significa que um operacional pode *criar* lançamentos que
  não vê. Mitigação: auditoria registra autoria; se precisar de rigor total, migrar
  para RPC `security definer` (item B, alternativa).
- O split de colaboradores exige migração de dados cuidadosa (não perder salários
  já cadastrados). Fazer backup/`select` antes do `drop column`.

---

## 6. Entregável
Quando aprovado, isto vira **uma migration** `supabase/migrations/2026XXXX_rls-por-role.sql`
(seções 1–2) + ajustes pontuais no `carregarTudo`/salvar colaborador no `index.html`
(seção 4). Estimativa: ~1 migration + ~40 linhas de JS.
