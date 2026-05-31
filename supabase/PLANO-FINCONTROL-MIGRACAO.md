# Plano — Migração direcionada do FinControl → Supabase

## Decisões (2026-05-31)
- **Escopo:** migrar só o que é usado de verdade (inventário real abaixo); ignorar o
  que está vazio (pipeline, NF, contratos, cobranças, templates, metas).
- **Financeiro unificado:** os lançamentos do FinControl entram na tabela
  `lancamentos` do app (fonte única). Fluxo de Caixa e FinControl passam a ver o mesmo.
- **Funcionários/sócios = colaboradores:** não migrar como entidade separada;
  reconciliar com `colaboradores` (por nome) e vincular.

## Inventário real (do localStorage, 2026-05-31)
| Recurso | Qtde | Destino |
|---|---|---|
| Lançamentos (`fc_lanc`) | 520 | → `lancamentos` (estendida) |
| Boletos/contas (`fc_boletos`) | 22 | → nova `contas_fin` (a pagar/receber) |
| Contas bancárias (`fc_contas_banc`) | 4 | → nova `contas_bancarias` |
| Centros de custo (`fc_centros`) | 4 | → nova `centros_custo` (ou texto em lancamentos) |
| Recorrentes (`fc_rec`) | 1 | → nova `recorrencias` |
| Categorias (`fc_cats`) | 1 | → merge em `categorias_financeiras` |
| Regras auto-cat (`fc_regras`) | 3 | → nova `regras_categoria` (opcional/baixa pri) |
| Funcionários (21) / Sócios (2) | 23 | reconciliar com `colaboradores` |
| Pessoas/CRM (3), Vendedores (2) | 5 | avaliar: fold em `clientes`/`colaboradores` |
| Pipeline, NF, contratos, cobranças, templates, metas | 0 | **ignorar** (vazios) |
| Log auditoria (200) | 200 | descartar (já há `auditoria` no app) |

## ⚠️ O ponto crítico: dado × UI
Migrar o **dado** é metade. A outra metade é a **UI**: o FinControl é um app à parte
(`fincontrol-v3.html`, iframe) que lê localStorage. Se migrarmos os dados para o
Supabase mas o iframe continuar lendo localStorage, ele não enxerga nada novo.
E o Fluxo de Caixa nativo **não tem** telas de boletos / contas bancárias / centros.

→ Logo, a migração exige **construir UI nativa** (no `index.html`, sobre Supabase)
para boletos, contas bancárias e centros — e então **aposentar o iframe**.
Isso é o que torna isto um projeto em fases, não um commit.

## Fases (cada uma entrega valor sozinha)

### Fase 0 — Segurança imediata (rápida, sem risco)
- **Exportar backup** de todos os `fc_*` (botão de backup do FinControl) — rede de
  proteção dos 520 lançamentos + boletos enquanto migramos.
- Remover o double-write (`fcLancar`) e corrigir o rótulo enganoso "Conectado ao
  Supabase" no card do FinControl.

### Fase 1 — Lançamentos unificados (núcleo)
- Estender `lancamentos` com: `forma text`, `centro text` (ou FK), `conciliado bool`,
  e um `origem text` (p/ rastrear 'oficina' vs 'fincontrol' e dedupe).
- Importador: 520 `fc_lanc` → `lancamentos`, **deduplicando** contra os lançamentos
  já gerados pela oficina (por origem/data/valor/descrição).
- Ajustar o Fluxo de Caixa nativo para exibir/filtrar tudo (já lê `lancamentos`).
- Aposentar `fc_lanc`.

### Fase 2 — Contas a pagar/receber + bancárias + centros
- Tabelas `contas_fin`, `contas_bancarias`, `centros_custo` (RLS por workspace).
- UI nativa no `index.html` (telas simples de CRUD + alertas de vencimento).
- Importar os 22 boletos, 4 contas, 4 centros.

### Fase 3 — Recorrências + categorias + regras
- `recorrencias` + merge de `fc_cats` em `categorias_financeiras` + (opcional)
  `regras_categoria` para auto-categorização.

### Fase 4 — Aposentar o iframe
- Remover `panel-fincontrol`/iframe e `fincontrol-v3.html`.
- Nav "FinControl Pro" → Fluxo de Caixa (que agora cobre tudo).

## Reconciliação de funcionários (transversal)
Antes de importar lançamentos de salário, casar os 23 funcionários/sócios do
FinControl com `colaboradores` por nome; criar os que faltarem; vincular por id.
Não criar entidade `funcionarios` separada.

## Riscos
- **Dedupe de lançamentos** é o ponto sensível (não duplicar o que a oficina já lançou).
  Mitigar com campo `origem` + chave (data+valor+descrição).
- **Backup obrigatório** antes da Fase 1 (importação) — dado real sem cópia hoje.
- Reescrever UI de boletos/contas é o maior esforço (Fase 2).

## Recomendação de execução
Começar pela **Fase 0 já** (backup + parar double-write/rótulo) — protege o dado e
limpa a confusão imediatamente. Depois Fase 1 (unificar lançamentos), que entrega o
sync do que mais importa. Fases 2–4 conforme prioridade.
