# Plano — FinControl & Planejamento → Supabase

## Descoberta principal: hoje existem DOIS sistemas financeiros em paralelo

| | Onde | Fonte de dados | Status |
|---|---|---|---|
| **Fluxo de Caixa** (nav, dono/socio) | `panel-fluxo-caixa` nativo | Supabase `lancamentos` + `pagamentos` | ✅ já é o sistema "de verdade", multi-dispositivo |
| **FinControl Pro** (nav, dono/socio) | `panel-fincontrol` = **iframe** de `fincontrol-v3.html` | **localStorage** `fc_lancamentos` (só do navegador) | ⚠️ legado redundante |

E há um **double-write**: os hooks `fcLancar()` ([index.html:6756+](index.html)) interceptam saída de OS, salário e compra de material e gravam em `localStorage.fc_lancamentos` — **os mesmos eventos que já vão para o Supabase** via `sbSalvarLancamento`. Ou seja, hoje cada saída/salário/compra é escrita **duas vezes** (uma no Supabase, outra no localStorage só para alimentar o iframe).

**Consequência para o plano:** "migrar FinControl → Supabase" não é reconstruir o `fincontrol-v3.html`. O financeiro **já está** no Supabase. O trabalho real é:
1. **Desativar o iframe legado** e parar o double-write.
2. **Migrar o Planejamento** (esse sim é localStorage puro, sem equivalente no Supabase).

---

## Inventário do localStorage

| Chave | Conteúdo | Destino |
|---|---|---|
| `fc_lancamentos` | lançamentos do FinControl iframe (espelho dos eventos) | ⚠️ ver decisão D1 |
| `om_plan_notas` | `{ 'YYYY-MM-DD': texto }` — anotações diárias | → Supabase |
| `om_plan_tarefas` | `[{id, semKey, feito, feitoEm, ...}]` — tarefas semanais | → Supabase |
| `om_plan_meta_fat` | `{ semKey: valor }` — meta de faturamento semanal | → Supabase |
| `om_metas_dias` | metas por dia | → Supabase |
| `om_meta_padrao` | `{seg:3,ter:3,...}` — meta padrão por dia da semana | → Supabase |
| `om_plan_config` | `{incluirSabado, incluirDomingo}` | → Supabase |
| `K_DARK` | preferência de tema | ✅ fica local (preferência por dispositivo) |
| `om_tour_done` | tour já visto | ✅ fica local |

---

## ⚠️ ATUALIZAÇÃO (2026-05-31) — Parte A REAVALIADA / EM ESPERA
Ao implementar, descobri que o `fincontrol-v3.html` (iframe) **NÃO é redundante**:
é um app financeiro completo com ~25 chaves próprias de localStorage —
`fc_lanc` (lançamentos reais), `fc_boletos`, `fc_rec` (recorrentes), `fc_func`,
`fc_metas`, `fc_nfs`, `fc_pipeline`, `fc_contratos`, `fc_socios`, `fc_pessoas`,
`fc_contas_banc`, etc. A chave `fc_lancamentos` (com "s") dos hooks é **outra** —
não é a que o app usa (`fc_lanc`).

Consequências:
- **Redirecionar/remover o menu (D2) esconderia um app cheio de dados reais.** ❌
- **Importar `fc_lancamentos` (D1)** traria só o espelho dos eventos da oficina, não
  os manuais (que estão em `fc_lanc` com estrutura própria). ❌
- Migrar o FinControl inteiro p/ Supabase é um **projeto próprio** (~10 tabelas +
  reescrever UI). Fora do escopo de um commit.

**Decisão:** Parte A **pausada** até replanejamento. Nada foi alterado no FinControl.
Opções a discutir: (1) deixar como app local e só remover o double-write/label
enganoso; (2) migrar incrementalmente só `fc_lanc` → `lancamentos` mantendo o resto
local; (3) projeto completo de migração do FinControl.

**Parte B (Planejamento) foi IMPLEMENTADA** — ver migration `20260531_planejamento.sql`
e mudanças no `index.html` (carregarTudo, CRUD de tarefas, blob, realtime, importador).

---

## Parte A — Desativar o FinControl iframe (baixo esforço, alto ganho) — OBSOLETO, ver atualização acima

**Recomendado (A1):**
1. Remover os hooks `fcLancar()` → acaba o double-write em localStorage.
2. Trocar o item de nav "FinControl Pro": ou removê-lo, ou fazer com que aponte para o **Fluxo de Caixa** (que já cobre receitas/salários/notas/seguradoras com dados Supabase).
3. Remover o `panel-fincontrol` (iframe) e, depois, o arquivo `fincontrol-v3.html` do repo.

**Decisão necessária (D1) — dados antigos do `fc_lancamentos`:**
Como os hooks espelhavam eventos que **já estão** em `lancamentos`, importar `fc_lancamentos` para `lancamentos` **duplicaria** receitas/salários/compras. Opções:
- **(a) Não importar** (recomendado): o histórico relevante já está no Supabase via Fluxo de Caixa. Mantém-se o `fc_lancamentos` intocado no navegador como backup, mas ele deixa de ser usado.
- **(b) Importar só o que for único**: se você lançou coisas **direto no app FinControl standalone** (não pelos hooks da oficina), esses registros não estão no Supabase. Aí precisamos de um importador com de-dup por (data+valor+descrição). Mais trabalho e sujeito a falsos positivos.

→ **Preciso que você confirme:** alguém usa o FinControl Pro (iframe) para lançar coisas que **não** passam pela oficina (ex.: despesas administrativas digitadas só lá)? Se não, seguimos com (a).

---

## Parte B — Planejamento → Supabase

### Schema proposto
Dois objetos, equilibrando simplicidade e necessidade de edição concorrente:

```sql
-- Blobs pequenos e de escrita esparsa (notas diárias, metas, config): 1 linha/workspace
create table public.planejamento (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  dados        jsonb not null default '{}'::jsonb,   -- { notas, metaFat, metasDias, metaPadrao, config }
  atualizado_em timestamptz not null default now()
);

-- Tarefas: lista que vários usuários editam → tabela relacional + realtime
create table public.planejamento_tarefas (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  sem_key      text not null,         -- ex.: '2026-W22'
  titulo       text not null,
  feito        boolean not null default false,
  feito_em     timestamptz,
  meta         jsonb not null default '{}'::jsonb,
  criado_em    timestamptz not null default now()
);
create index on public.planejamento_tarefas(workspace_id, sem_key);
```

### RLS
Planejamento é visível a `dono,socio,gerente,assistente` (nav). Como não é dado
sensível financeiro, usar **isolamento por workspace** (igual ao operacional):
```sql
create policy "plan_all" on public.planejamento for all
  using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());
create policy "plan_tarefas_all" on public.planejamento_tarefas for all
  using (workspace_id = public.meu_workspace_id())
  with check (workspace_id = public.meu_workspace_id());
```
Realtime: adicionar `planejamento_tarefas` à publicação para sync entre usuários.

### Mudanças no cliente (index.html)
- Carregar `planejamento`/`planejamento_tarefas` no `carregarTudo`.
- Trocar os `localStorage.getItem/setItem('om_plan_*')` por leitura/escrita no Supabase
  (funções `_savePlanNotas/Tarefas/MetaFat` → upsert no Supabase, com debounce).
- Tratar as tarefas via `sb*` (insert/update/delete) e refletir no Realtime.

### Migração dos dados existentes (importador único, não-destrutivo)
No primeiro load após o deploy, se houver `om_plan_*` no localStorage e a flag
`om_plan_migrado` não existir:
1. `upsert` em `planejamento.dados` = { notas, metaFat, metasDias, metaPadrao, config }.
2. `insert` das tarefas em `planejamento_tarefas`.
3. Marcar `localStorage.om_plan_migrado='1'` (mantém o localStorage como backup; não apaga).

---

## Ordem de execução proposta
1. **Parte A** primeiro (rápida, remove redundância e o double-write).
2. **Parte B** depois (migration SQL + ~80-120 linhas de cliente + importador).

## Decisões tomadas (2026-05-30)
- **D1 → importar os manuais, com de-dup por origem.** Há despesas da oficina (já no
  Supabase via hooks) **e** despesas digitadas manualmente no FinControl. Estratégia:
  importar de `fc_lancamentos` **apenas** os registros com `origem !== 'oficina_manager'`
  (os manuais; os de origem `oficina_manager` já estão em `lancamentos` e seriam
  duplicata). ⚠️ Ao implementar, confirmar no `fincontrol-v3.html` a forma exata dos
  registros manuais (campos data/valor/descrição/categoria) para mapear corretamente.
- **D2 → redirecionar.** O item de nav "FinControl Pro" passa a abrir o **Fluxo de
  Caixa** (não remover, para não estranhar quem conhece o nome).
- **D3 → blob + tabela de tarefas** (schema acima).

## Plano de implementação (sequência)
**Parte A — consolidar o financeiro**
1. Remover os hooks `fcLancar()` (acaba o double-write em localStorage).
2. Nav "FinControl Pro" → `showPanel('fluxo-caixa', ...)`; remover `panel-fincontrol`/iframe.
3. **Importador de manuais** (one-time, não-destrutivo): ler `fc_lancamentos`, filtrar
   `origem !== 'oficina_manager'`, `insert` em `lancamentos`, marcar `om_fc_migrado='1'`.
4. Remover `fincontrol-v3.html` do repo (passo final).

**Parte B — Planejamento**
5. Migration: tabelas `planejamento` + `planejamento_tarefas` + RLS + realtime.
6. Cliente: carregar no `carregarTudo`; trocar `_savePlan*` por upsert Supabase (debounce);
   tarefas via insert/update/delete + realtime.
7. Importador one-time dos `om_plan_*` (não-destrutivo, flag `om_plan_migrado`).

## Estimativa
- Parte A: ~1 importador + remoção de hooks/iframe/nav.
- Parte B: ~1 migration + ~100-120 linhas de cliente + importador.
