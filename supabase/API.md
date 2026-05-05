# Oficina Manager — Referência de API

> A API é fornecida automaticamente pelo **PostgREST** do Supabase.
> Toda chamada exige o header `Authorization: Bearer <JWT>` obtido no login.

**Base URL:** `https://SEU_PROJETO.supabase.co/rest/v1`

---

## Autenticação

### POST `/auth/v1/token?grant_type=password`
Login com e-mail e senha.
```json
// Body
{ "email": "admin@oficina.com", "password": "senha123" }

// Response 200
{
  "access_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": { "id": "uuid", "email": "..." }
}
```

### POST `/auth/v1/logout`
Invalida a sessão atual.

---

## Veículos / Ordens de Serviço

### GET `/veiculos`
Lista todos os veículos do workspace (RLS filtra automaticamente).
```
GET /veiculos?select=*,orcamento_itens(*)&order=criado_em.desc
```

Filtros úteis:
```
?status=eq.em-andamento          # apenas em andamento
?placa=ilike.*ABC*               # busca por placa
?cliente_id=eq.{uuid}            # por cliente
```

### POST `/veiculos`
Criar nova OS.
```json
{
  "placa": "ABC-1234",
  "modelo": "Fiat Uno",
  "servico": "Pintura",
  "status": "aguardando",
  "workspace_id": "uuid-do-workspace"
}
```

### PATCH `/veiculos?id=eq.{id}`
Atualizar. Exemplo: mover no Kanban.
```json
{ "status": "em-andamento" }
```

### DELETE `/veiculos?id=eq.{id}`
Excluir OS (cascata remove itens, fotos, notas).

---

## Clientes

### GET `/clientes?order=nome`
### POST `/clientes`
```json
{ "nome": "João Silva", "telefone": "11999999999", "workspace_id": "..." }
```
### PATCH `/clientes?id=eq.{id}`
### DELETE `/clientes?id=eq.{id}`

---

## Colaboradores

### GET `/colaboradores?ativo=eq.true`
### POST `/colaboradores`
### PATCH `/colaboradores?id=eq.{id}`
### PATCH `/colaboradores?id=eq.{id}` — desativar
```json
{ "ativo": false }
```

---

## Pagamentos / Caixa

### GET `/pagamentos?order=data.desc`
```
?tipo=eq.entrada&data=gte.2026-01-01    # entradas do ano
```
### POST `/pagamentos`
```json
{
  "tipo": "entrada",
  "descricao": "Serviço - Fiat Uno",
  "valor": 850.00,
  "forma": "pix",
  "data": "2026-05-04",
  "workspace_id": "..."
}
```

---

## Lançamentos Financeiros

### GET `/lancamentos?order=data.desc`
### POST `/lancamentos`
```json
{
  "tipo": "saida",
  "descricao": "Compra de tinta",
  "valor": 320.00,
  "categoria": "Compra de peças",
  "data": "2026-05-04",
  "workspace_id": "..."
}
```

---

## Estoque

### GET `/estoque?order=nome`
```
?quantidade=lt.estoque_min   # itens abaixo do mínimo (coluna calculada)
```
### POST `/estoque`
### PATCH `/estoque?id=eq.{id}`
```json
{ "quantidade": 15 }
```

---

## Agenda

### GET `/agenda?data=gte.2026-05-01&data=lte.2026-05-31&order=data,hora`
### POST `/agenda`
### DELETE `/agenda?id=eq.{id}`

---

## Parcelas

### GET `/parcelas?pago=eq.false&order=vencimento`
### PATCH `/parcelas?id=eq.{id}` — marcar como pago
```json
{ "pago": true, "pago_em": "2026-05-04T10:30:00Z" }
```

---

## Usuários / Perfis

### GET `/profiles?workspace_id=eq.{wid}`
Lista membros da oficina.

### PATCH `/profiles?id=eq.{id}` — alterar role
```json
{ "role": "gerente" }
```

### RPC: convidar novo membro
```
POST /rpc/adicionar_membro
{
  "p_user_id": "uuid",
  "p_workspace_id": "uuid",
  "p_nome": "Maria",
  "p_username": "maria",
  "p_role": "operador"
}
```

---

## Realtime (WebSocket)

```javascript
// Escutar mudanças em veiculos do workspace
db.channel('veiculos-live')
  .on('postgres_changes', {
    event: '*',
    schema: 'public',
    table: 'veiculos',
    filter: `workspace_id=eq.${wid}`
  }, (payload) => {
    console.log(payload.eventType, payload.new);
  })
  .subscribe();
```

Eventos: `INSERT` | `UPDATE` | `DELETE`

---

## Storage (Fotos)

```javascript
// Upload
const { data } = await db.storage
  .from('fotos')
  .upload(`${wid}/${veiculoId}/foto.jpg`, file);

// URL pública
const { data: { publicUrl } } = db.storage
  .from('fotos')
  .getPublicUrl(`${wid}/${veiculoId}/foto.jpg`);
```

---

## Códigos de Erro

| HTTP | Significado |
|---|---|
| 401 | Token ausente ou expirado — fazer login novamente |
| 403 | RLS bloqueou o acesso — workspace incorreto |
| 409 | Conflito de unicidade (ex: slug duplicado) |
| 422 | Violação de constraint (ex: role inválido) |
| 500 | Erro interno — verificar logs no Dashboard |
