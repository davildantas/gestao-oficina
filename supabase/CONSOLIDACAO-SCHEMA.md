# Runbook — Consolidar o schema real do Supabase no repositório

**Objetivo:** fazer o repositório voltar a ser a fonte de verdade do banco, capturando
o estado REAL de produção (que hoje diverge dos `.sql` versionados — ver
`RLS-PROPOSAL.md` e o app usando colunas/RPCs inexistentes no repo).

> **Por que é delicado:** as migrations atuais foram aplicadas **manualmente pelo
> SQL Editor**, não via `supabase db push`. Logo, a tabela de histórico do CLI
> (`supabase_migrations.schema_migrations`) provavelmente está **vazia**. Se você
> rodar `db push` sem reconciliar, o CLI tentará reaplicar TODAS as migrations
> locais — inclusive as já aplicadas — e vai dar erro (objetos duplicados).
> O fluxo abaixo evita isso fazendo um **baseline** do estado real.

---

## 0. Pré-requisitos

```bash
# Instalar o CLI (macOS)
brew install supabase/tap/supabase
supabase --version

# Autenticar
supabase login            # abre o navegador / pede um access token
```

- Tenha em mãos a **senha do banco** (Dashboard → Project Settings → Database).
- **Faça backup** antes de qualquer push: Dashboard → Database → Backups.

## 1. Trabalhe num branch git

```bash
cd /Users/davi/Desktop/ConsertCar/Melhorias
git checkout -b chore/consolidar-schema
```

## 2. Linkar o projeto

```bash
supabase link --project-ref ogjkllypbzvggetkrcbv
```
Isso (re)cria `supabase/config.toml`. O ref já está em `supabase/.temp/project-ref`.

## 3. Tirar uma "foto" do schema REAL (baseline)

```bash
# Pasta separada para não misturar com as migrations antigas
supabase db dump --schema public -f supabase/_baseline_producao.sql
```
Esse arquivo é o estado verdadeiro do banco AGORA — a referência para conferir o
que o repo não tinha (estoque.codigo/fornecedor, movimentar_estoque,
estoque_movimentacoes, colaboradores.tel/status/cargo, seguradoras, etc.).

## 4. Reconciliar o histórico de migrations

Decida uma das duas estratégias:

### Estratégia A — Recomeçar o histórico a partir do baseline (mais simples)
1. Mova as migrations antigas para fora do caminho do CLI:
   ```bash
   mkdir -p supabase/migrations_legado
   git mv supabase/migrations/*.sql supabase/migrations_legado/
   ```
   (Mantém histórico no git, tira do push.)
2. Gere a migration-baseline a partir do estado real:
   ```bash
   supabase db pull            # cria supabase/migrations/<ts>_remote_schema.sql
   ```
   Esse arquivo passa a ser o ponto de partida único e fiel.
3. Marque o baseline como já aplicado em produção (não reaplicar):
   ```bash
   supabase migration list                       # veja o timestamp gerado
   supabase migration repair --status applied <timestamp_do_baseline>
   ```

### Estratégia B — Manter os arquivos e só sincronizar o histórico
Para cada migration antiga **já aplicada** manualmente, marque como applied:
```bash
supabase migration repair --status applied 0002 melhorias-2026-05 20260527 convites
```
(use os timestamps que aparecem em `supabase migration list`). Mais trabalhosa e
sujeita a erro porque os nomes atuais não seguem o padrão de timestamp do CLI —
por isso a **Estratégia A é a recomendada**.

## 5. Aplicar as DUAS migrations novas desta rodada

As correções desta sessão ainda **não** estão em produção:
- `20260530_correcoes-rapidas.sql`
- `20260530_rls-por-role.sql`  ⚠️ destrutiva (split de colaboradores — backup!)

Depois do baseline reconciliado, coloque-as em `supabase/migrations/` (com timestamp
no formato do CLI, ex.: `20260530120000_correcoes_rapidas.sql`) e rode:
```bash
supabase db push          # aplica só o que falta, conferindo o histórico
```
> Alternativa sem CLI: aplicar as duas pelo SQL Editor (como as anteriores) e depois
> `supabase migration repair --status applied <ts>` para o histórico não tentar
> reaplicá-las.

## 6. Validar

```bash
supabase db diff          # deve vir VAZIO (repo == produção)
```
Teste no app com um usuário de cada role (ver checklist em `RLS-PROPOSAL.md` §5).

## 7. Higiene contínua (a partir de agora)

- **Nunca mais** edite o banco pelo SQL Editor sem criar uma migration correspondente.
- Fluxo padrão: `supabase migration new <nome>` → escreve o SQL → `supabase db push`.
- `supabase/.temp/` já está no `.gitignore` (não versionar estado local do CLI).
- Rode `supabase db diff` no CI/antes de cada deploy para detectar drift cedo.

---

### Resumo do que EU já deixei pronto
- `.gitignore` com `supabase/.temp/`.
- As 2 migrations novas (correções + RLS por role).
- Este runbook.

### O que precisa de VOCÊ (exige CLI + senha do banco + backup — não posso executar)
- Passos 0–6 acima. O passo 3 (`db dump`) é o mais importante: é a foto fiel que
  finalmente coloca o repo em dia com a produção.
