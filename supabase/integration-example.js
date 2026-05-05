// =============================================================
// GUIA DE INTEGRAÇÃO — Como adaptar oficina-manager-v4.html
// =============================================================
// Este arquivo mostra as mudanças necessárias no HTML original.
// Não é um arquivo para rodar diretamente — é um guia de migração
// com exemplos de antes/depois para cada padrão de código.
// =============================================================

// ─── 1. ADICIONAR NO <head> DO HTML ───────────────────────────
/*
<!-- Supabase JS SDK (antes do script principal) -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
<script src="supabase/client.js"></script>
<script src="supabase/migration-script.js"></script>
*/

// ─── 2. INICIALIZAÇÃO ─────────────────────────────────────────

// ANTES (localStorage):
// let users = JSON.parse(localStorage.getItem('om_users') || '[]');
// let veiculos = JSON.parse(localStorage.getItem('om_veiculos') || '[]');
// ... (12 variáveis separadas)

// DEPOIS (Supabase):
// Todas as variáveis vêm de DB.* após login.
// Substitua as 12 declarações iniciais por:

async function init() {
  const sessao = await sbVerificarSessao();
  if (sessao) {
    // Usuário já logado — carregar UI principal
    session = DB.session;
    users     = DB.users;
    colabs    = DB.colabs;
    veiculos  = DB.veiculos;
    pagamentos= DB.pagamentos;
    config    = DB.config;
    clientes  = DB.clientes;
    agenda    = DB.agenda;
    estoque   = DB.estoque;
    auditoria = DB.auditoria;
    metas     = DB.metas;
    fila      = DB.fila;
    fotos     = DB.fotos;
    parcelas  = DB.parcelas;
    notas     = DB.notas;
    satisf    = DB.satisf;

    mostrarApp();
    sbInscreverRealtime(onRealtimeUpdate);
  } else {
    mostrarLogin();
  }
}

// ─── 3. LOGIN ─────────────────────────────────────────────────

// ANTES:
// function doLogin() {
//   const u = users.find(u => u.username === inputUser.value && checkPass(inputPass.value, u.pass));
//   if (u) { session = u; localStorage.setItem('om_session', ...); }
// }

// DEPOIS:
async function doLogin() {
  const email = document.getElementById('inp-user').value.trim();
  const senha = document.getElementById('inp-pass').value;
  try {
    await sbLogin(email, senha);
    // sbLogin já chama carregarTudo() internamente
    session   = DB.session;
    veiculos  = DB.veiculos;
    clientes  = DB.clientes;
    // ... demais variáveis
    mostrarApp();
    sbInscreverRealtime(onRealtimeUpdate);
  } catch (e) {
    toast('Usuário ou senha incorretos', 'error');
  }
}

// ─── 4. SALVAMENTO ────────────────────────────────────────────

// ANTES:
// function salvarTudo() {
//   localStorage.setItem('om_veiculos', JSON.stringify(veiculos));
//   localStorage.setItem('om_clientes', JSON.stringify(clientes));
//   // ... etc
// }

// DEPOIS: cada entidade tem sua própria função assíncrona.
// Substitua as chamadas de salvarTudo() pela função correspondente.

// Exemplo — salvar/atualizar veículo:
// ANTES:
// function salvarVeiculo(v) {
//   const idx = veiculos.findIndex(x => x.id === v.id);
//   if (idx >= 0) veiculos[idx] = v; else veiculos.push(v);
//   salvarTudo();
// }

// DEPOIS:
async function salvarVeiculoIntegrado(v) {
  try {
    const id = await sbSalvarVeiculo(v);
    // Atualiza array local (Realtime também fará isso automaticamente)
    const idx = veiculos.findIndex(x => x.id === v.id);
    if (idx >= 0) veiculos[idx] = { ...v, id };
    else veiculos.push({ ...v, id });
    renderKanban();
    toast('Salvo com sucesso', 'success');
  } catch (e) {
    toast('Erro ao salvar: ' + e.message, 'error');
  }
}

// ─── 5. REALTIME — callback de atualização ────────────────────

function onRealtimeUpdate(tabela, evento, registro) {
  // Quando outro computador altera dados, esta função é chamada.
  // Re-renderize apenas o componente afetado.
  switch (tabela) {
    case 'veiculos':
      renderKanban();
      break;
    case 'pagamentos':
      renderCaixa();
      break;
    case 'estoque':
      renderEstoque();
      break;
    case 'agenda':
      renderAgenda();
      break;
    case 'fila':
      renderFila();
      break;
    case 'notas':
      renderNotas();
      break;
  }
  // Toast opcional para avisar o usuário
  if (evento === 'INSERT') {
    toast(`Novo registro em ${tabela} (outro usuário)`, 'info');
  }
}

// ─── 6. LOGOUT ────────────────────────────────────────────────

// ANTES:
// function doLogout() { localStorage.removeItem('om_session'); session=null; location.reload(); }

// DEPOIS:
async function doLogout() {
  await sbLogAudit('logout', DB.session?.username + ' saiu');
  await sbLogout();
  session = null;
  location.reload();
}

// ─── 7. KANBAN — mover veículo ────────────────────────────────

// ANTES:
// function moverStatus(id, novoStatus) {
//   const v = veiculos.find(x => x.id === id);
//   if (v) { v.status = novoStatus; salvarTudo(); renderKanban(); }
// }

// DEPOIS:
async function moverStatus(id, novoStatus) {
  try {
    await sbMoverKanban(id, novoStatus);
    // Realtime atualiza automaticamente nos outros clientes
    // Atualiza local imediatamente para feedback instantâneo
    const v = veiculos.find(x => x.id === id);
    if (v) v.status = novoStatus;
    renderKanban();
  } catch (e) {
    toast('Erro ao mover: ' + e.message, 'error');
  }
}

// ─── 8. ESTOQUE — ajustar quantidade ─────────────────────────

// ANTES:
// function ajustarEstoque(id, delta) {
//   const item = estoque.find(e => e.id === id);
//   if (item) { item.quantidade += delta; salvarTudo(); }
// }

// DEPOIS — use RPC para evitar race condition com múltiplos usuários:
// (adicione esta função no schema.sql)
/*
create or replace function public.ajustar_estoque(p_id uuid, p_delta numeric)
returns void language sql security definer as $$
  update public.estoque
  set quantidade = quantidade + p_delta, atualizado_em = now()
  where id = p_id and workspace_id = meu_workspace_id();
$$;
*/

async function ajustarEstoque(id, delta) {
  await sbAjustarEstoque(id, delta);
  // Realtime atualiza DB.estoque[] automaticamente
}

// ─── 9. AUDITORIA ─────────────────────────────────────────────

// ANTES:
// function logAudit(acao, detalhe) {
//   auditoria.unshift({ ts: Date.now(), user: session.username, acao, detalhe });
//   localStorage.setItem('om_auditoria', JSON.stringify(auditoria));
// }

// DEPOIS:
async function logAudit(acao, detalhe) {
  await sbLogAudit(acao, detalhe);
  // Adiciona ao array local para exibição imediata
  auditoria.unshift({ acao, detalhe, username: DB.session.username, criado_em: new Date().toISOString() });
}

// ─── 10. UPLOAD DE FOTOS ──────────────────────────────────────

// ANTES: fotos eram base64 salvas no localStorage (problemático — limite de 5MB)

// DEPOIS:
async function uploadFoto(veiculoId, inputFile) {
  const file = inputFile.files[0];
  if (!file) return;
  try {
    const url = await sbUploadFoto(veiculoId, file);
    renderFotos(veiculoId); // re-renderiza galeria
    toast('Foto enviada!', 'success');
  } catch (e) {
    toast('Erro no upload: ' + e.message, 'error');
  }
}

// ─── 11. FORMULÁRIO DE NOVO USUÁRIO ───────────────────────────

// ANTES: adicionava ao array users[] e salvava no localStorage

// DEPOIS:
async function criarUsuario(email, senha, nome, username, role) {
  // Fluxo de convite: Supabase envia e-mail de confirmação.
  // Após o usuário confirmar, o webhook on-signup.ts cria o profile.
  const { error } = await db.auth.admin.inviteUserByEmail(email, {
    data: { nome, username, role, workspace_id: wsId() }
  });
  if (error) { toast('Erro: ' + error.message, 'error'); return; }

  // Cria o profile imediatamente (sem esperar confirmação)
  // — útil para convites internos onde você confia no e-mail.
  // Comente se quiser aguardar confirmação.
  toast(`Convite enviado para ${email}`, 'success');
}

// ─── 12. MIGRAÇÃO DOS DADOS ANTIGOS ───────────────────────────

// Chame uma única vez no console do navegador que tem os dados:
// await migrarTudo()
//
// Veja migration-script.js para detalhes completos.

// ─── 13. CHECKLIST DE MIGRAÇÃO DO HTML ───────────────────────
/*
Passos para integrar o client.js no oficina-manager-v4.html:

[ ] 1. Adicionar CDN do Supabase no <head> (antes do script principal)
[ ] 2. Adicionar <script src="supabase/client.js"></script>
[ ] 3. Substituir as 12 declarações let/localStorage no topo do script
       por: chamada ao init() no DOMContentLoaded
[ ] 4. Substituir doLogin() pela versão async
[ ] 5. Substituir doLogout() pela versão async
[ ] 6. Substituir salvarTudo() → funções sbSalvar* por módulo
[ ] 7. Substituir hashPass/checkPass → removidos (Auth do Supabase)
[ ] 8. Substituir logAudit() pela versão async
[ ] 9. Adicionar sbInscreverRealtime() após login
[ ] 10. Testar com 2 navegadores simultaneamente
[ ] 11. Rodar migrarTudo() no computador com dados legados
[ ] 12. Verificar dados no Supabase Table Editor
*/
