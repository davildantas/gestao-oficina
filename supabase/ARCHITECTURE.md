# Oficina Manager — Arquitetura Multi-Usuário

## Visão Geral

```
┌─────────────────────────────────────────────────────────────────┐
│                        NAVEGADORES                              │
│  Computador 1       Computador 2       Computador 3             │
│  ┌──────────┐        ┌──────────┐      ┌──────────┐             │
│  │HTML+JS   │        │HTML+JS   │      │HTML+JS   │             │
│  │client.js │        │client.js │      │client.js │             │
│  └────┬─────┘        └────┬─────┘      └────┬─────┘             │
└───────┼──────────────────┼───────────────────┼──────────────────┘
        │ HTTPS            │ HTTPS             │ HTTPS
        │ (REST + Realtime WebSocket)           │
┌───────▼──────────────────▼───────────────────▼──────────────────┐
│                        SUPABASE                                  │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │  PostgREST   │  │  Realtime    │  │  Supabase Auth        │  │
│  │  (REST API)  │  │  (WebSocket) │  │  (JWT + OAuth)        │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬────────────┘  │
│         │                 │                      │               │
│  ┌──────▼─────────────────▼──────────────────────▼────────────┐  │
│  │               PostgreSQL (RLS habilitado)                   │  │
│  │   workspaces │ profiles │ veiculos │ clientes │ pagamentos  │  │
│  │   agenda │ estoque │ lancamentos │ auditoria │ ...          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │   Storage    │  │ Edge Functions│                             │
│  │   (Fotos)    │  │ (on-signup)  │                             │
│  └──────────────┘  └──────────────┘                             │
└──────────────────────────────────────────────────────────────────┘
```

## Stack de Tecnologia

| Camada | Tecnologia | Motivo |
|---|---|---|
| Frontend | HTML/CSS/JS (existente) | Sem reescrita; apenas a camada de dados muda |
| API + Auth | Supabase (PostgREST + GoTrue) | Sem backend próprio; API auto-gerada pelo schema |
| Banco de Dados | PostgreSQL (Supabase) | Relacional, RLS nativo, Realtime via Logical Replication |
| Realtime | Supabase Realtime | WebSocket gerenciado; canais filtrados por workspace |
| Storage | Supabase Storage | Fotos dos veículos com URL pública por workspace |
| Deploy Frontend | Netlify / Vercel / GitHub Pages | CDN global, HTTPS automático |
| Edge Functions | Supabase Edge Functions (Deno) | Webhook de signup, lógica server-side pontual |

## Multi-Tenancy

Cada oficina é um **workspace**. Todos os registros carregam `workspace_id`.
O RLS (Row Level Security) garante isolamento: a função `meu_workspace_id()`
lê o `workspace_id` do perfil do usuário autenticado e filtra automaticamente
todas as queries — sem nenhum código adicional no frontend.

## Roles / Permissões

| Role | Pode fazer |
|---|---|
| `dono` | Tudo, incluindo criar usuários, editar config, ver auditoria |
| `gerente` | Operações financeiras, relatórios, estoque, agenda |
| `operador` | Kanban, agenda, visualizar veículos; sem acesso financeiro |

As restrições de role são implementadas no **cliente** (ocultando seções da UI)
e reforçadas via **RLS policies** adicionais para operações críticas.

## Fluxo de Dados (exemplo: mover veículo no Kanban)

```
Usuário A (Comp 1) drag-and-drop veículo
  → sbMoverKanban(id, 'em-andamento')
    → PATCH /rest/v1/veiculos?id=eq.{id}
      → PostgreSQL UPDATE (RLS valida workspace)
        → Supabase Realtime detecta mudança via WAL
          → WebSocket broadcast para todos no workspace
            → aplicarMudancaLocal() atualiza DB.veiculos[]
              → onUpdate() re-renderiza Kanban no Comp 2 e Comp 3
```

## Deploy

### Frontend
```bash
# Netlify
netlify deploy --dir . --prod

# Vercel
vercel --prod
```

### Supabase
```bash
# 1. Criar projeto em supabase.com
# 2. Aplicar schema
supabase db push < supabase/schema.sql

# 3. Deploy da Edge Function
supabase functions deploy on-signup

# 4. Configurar webhook de Auth no Dashboard:
#    Auth → Hooks → After user created
#    URL: https://SEU_PROJETO.supabase.co/functions/v1/on-signup

# 5. Criar bucket de storage
supabase storage create fotos --public
```

### Variáveis de Ambiente
```
SUPABASE_URL=https://SEU_PROJETO.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...  (segura expor no frontend)
```

## Segurança

- Chave `anon` exposta no frontend — segura, pois RLS impede acesso entre workspaces.
- Chave `service_role` usada **apenas** nas Edge Functions (nunca no frontend).
- JWT expira em 1h (padrão Supabase); `autoRefreshToken: true` renova silenciosamente.
- Senhas gerenciadas pelo Supabase Auth (bcrypt) — o sistema legado de hash simples é descartado.
- HTTPS obrigatório (Supabase e Netlify/Vercel fornecem automaticamente).

## Migração de Dados

1. Faça login no novo sistema com a conta admin.
2. Abra o console do navegador **no computador que tem os dados antigos**.
3. Certifique-se de que `migration-script.js` está carregado.
4. Execute: `await migrarTudo()`
5. Aguarde a conclusão e recarregue a página.
6. Verifique os dados no Supabase Dashboard → Table Editor.

## Escalabilidade

- Supabase Free: até 500 MB de banco, 2 GB de transfer — suficiente para início.
- Supabase Pro ($25/mês): 8 GB banco, sem limite de conexões, backups diários.
- O schema é multi-tenant desde o início: adicionar novas oficinas não requer mudança de infraestrutura.
- Conexões ao banco são gerenciadas pelo PgBouncer (pooling automático do Supabase).
