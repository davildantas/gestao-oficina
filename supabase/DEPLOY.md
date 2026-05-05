# Guia de Deploy — Oficina Manager Multi-Usuário

## Pré-requisitos

- Conta no [supabase.com](https://supabase.com) (gratuita)
- Node.js 18+ e `npm` instalados (apenas para o CLI)
- Conta no [Netlify](https://netlify.com) ou [Vercel](https://vercel.com) (gratuita)

---

## Passo 1 — Criar Projeto no Supabase

1. Acesse [supabase.com/dashboard](https://supabase.com/dashboard)
2. Clique em **New Project**
3. Escolha um nome (ex: `oficina-manager`) e uma senha forte para o banco
4. Selecione a região mais próxima (ex: `South America (São Paulo)`)
5. Aguarde o projeto inicializar (~2 min)

---

## Passo 2 — Aplicar o Schema

No Dashboard do Supabase, vá em **SQL Editor** e execute o conteúdo de `supabase/schema.sql`:

```sql
-- Cole todo o conteúdo de schema.sql aqui e clique em Run
```

Ou via CLI (após autenticar com `supabase login`):
```bash
supabase link --project-ref SEU_PROJECT_REF
supabase db push < supabase/schema.sql
```

---

## Passo 3 — Configurar Storage

No Dashboard: **Storage → New bucket**
- Nome: `fotos`
- Marque **Public bucket** (URLs públicas para exibir fotos)

Adicione esta política no bucket (SQL Editor):
```sql
create policy "fotos_workspace" on storage.objects
  for all using (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = public.meu_workspace_id()::text
  );
```

---

## Passo 4 — Deploy da Edge Function

```bash
# Instalar CLI do Supabase
npm install -g supabase

# Login
supabase login

# Linkar ao projeto
supabase link --project-ref SEU_PROJECT_REF

# Deploy da função de signup
supabase functions deploy on-signup --no-verify-jwt
```

No Dashboard: **Auth → Hooks → After user created**
- URL: `https://SEU_PROJETO.supabase.co/functions/v1/on-signup`
- HTTP Method: POST

---

## Passo 5 — Configurar o Frontend

Edite `supabase/client.js` e substitua:
```javascript
const SUPABASE_URL  = 'https://SEU_PROJETO.supabase.co';
const SUPABASE_ANON = 'eyJhbGc...';
```

Você encontra esses valores em: **Dashboard → Settings → API**
- `Project URL` → `SUPABASE_URL`
- `anon / public` key → `SUPABASE_ANON`

> ⚠️ Use SEMPRE a chave `anon` no frontend. Nunca exponha a `service_role`.

---

## Passo 6 — Deploy do Frontend

### Opção A: Netlify (recomendado)

1. Faça upload da pasta `Melhorias/` em [netlify.com/drop](https://app.netlify.com/drop)
   - Ou conecte ao GitHub para deploy automático

2. Configure as variáveis de ambiente (opcional, se usar build):
   ```
   SUPABASE_URL=https://...
   SUPABASE_ANON_KEY=eyJ...
   ```

### Opção B: Vercel

```bash
npm install -g vercel
vercel --prod
```

### Opção C: GitHub Pages

Faça push para um repositório público e ative Pages na branch `main`.

---

## Passo 7 — Primeiro Acesso e Migração

1. Acesse a URL do seu frontend
2. Clique em **Criar conta / Nova oficina** e registre o primeiro usuário (dono)
3. Faça login
4. **No computador que tem os dados antigos:**
   - Abra o site no navegador (com dados do localStorage ainda presentes)
   - Abra o console (F12 → Console)
   - Execute: `await migrarTudo()`
   - Aguarde a mensagem `✅ Migração concluída!`
5. Recarregue a página — todos os dados estarão na nuvem

---

## Passo 8 — Adicionar Usuários

No sistema, vá em **Configurações → Usuários**:
- Insira o e-mail do novo colaborador
- Escolha o role: `gerente` ou `operador`
- O Supabase enviará um e-mail de convite automaticamente

---

## Configuração de Domínio Personalizado (opcional)

### Netlify
- Settings → Domain management → Add custom domain

### Supabase Auth (importante!)
- Dashboard → Auth → URL Configuration
- **Site URL:** `https://seu-dominio.com`
- **Redirect URLs:** `https://seu-dominio.com/**`

---

## Monitoramento e Backups

| O que | Onde |
|---|---|
| Logs de API | Dashboard → Logs → API |
| Logs de Auth | Dashboard → Logs → Auth |
| Logs de Edge Functions | Dashboard → Logs → Edge Functions |
| Backups automáticos | Dashboard → Database → Backups (Pro plan) |
| Uso e limites | Dashboard → Settings → Usage |

### Backup manual (Free plan)
```bash
supabase db dump --local > backup-$(date +%Y%m%d).sql
```

---

## Custos Estimados

| Plano | Preço | Limite de banco | Usuários |
|---|---|---|---|
| Supabase Free | $0/mês | 500 MB | Ilimitado |
| Supabase Pro | $25/mês | 8 GB | Ilimitado |
| Netlify Free | $0/mês | - | - |

Para uma oficina pequena, o **plano gratuito** de ambas as plataformas é suficiente.

---

## Troubleshooting

**Erro 401 na API**
→ Token expirou. O `autoRefreshToken: true` deve renovar automaticamente.
→ Verifique se `SUPABASE_ANON` está correto no client.js.

**Realtime não recebe eventos**
→ Confirme que `alter publication supabase_realtime add table ...` foi executado.
→ No Dashboard: Database → Replication → verifique as tabelas.

**RLS bloqueando queries**
→ Certifique-se de estar logado (token JWT no header).
→ Verifique se `meu_workspace_id()` retorna um valor não-nulo.

**Fotos não aparecem**
→ Confirme que o bucket `fotos` é público.
→ Verifique se a política de storage foi criada.
