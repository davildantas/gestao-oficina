// =============================================================
// OFICINA MANAGER — Supabase Client Layer
// Substitui todas as chamadas de localStorage por chamadas ao Supabase.
// Inclua este arquivo ANTES do script principal do app.
//
// Dependência (CDN — adicione no <head> do HTML):
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
// =============================================================

const SUPABASE_URL  = 'https://ogjkllypbzvggetkrcbv.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9namtsbHlwYnp2Z2dldGtyY2J2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDAxNDMsImV4cCI6MjA5MzQ3NjE0M30.EnQDck7fvFmU157Sz-ueHnxIXub2a7c1d9sr4DwyB3A';

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: { persistSession: true, autoRefreshToken: true }
});

// ─── ESTADO GLOBAL (espelha o localStorage original) ──────────
// O app continua usando estas variáveis em memória; a diferença é
// que a persistência passa pelo Supabase e a sincronização em tempo
// real atualiza essas variáveis automaticamente.
let DB = {
  session:      null,   // { id, nome, username, role, workspace_id }
  users:        [],
  colabs:       [],
  veiculos:     [],
  pagamentos:   [],
  config:       {},
  clientes:     [],
  agenda:       [],
  estoque:      [],
  auditoria:    [],
  metas:        {},
  fila:         [],
  fotos:        {},
  parcelas:     [],
  notas:        [],
  satisf:       [],
  lancamentos:  [],
  categorias:   { entrada: [], saida: [] },
};

// ─── HELPERS ──────────────────────────────────────────────────
function wsId() {
  if (!DB.session?.workspace_id) throw new Error('Sem workspace ativo');
  return DB.session.workspace_id;
}

async function handle(promise) {
  const { data, error } = await promise;
  if (error) { console.error('[Supabase]', error.message); throw error; }
  return data;
}

// ─── AUTENTICAÇÃO ─────────────────────────────────────────────

/** Login com e-mail + senha (Supabase Auth) */
async function sbLogin(email, senha) {
  const { data, error } = await db.auth.signInWithPassword({ email, password: senha });
  if (error) throw error;

  // Carrega perfil do usuário
  const profile = await handle(
    db.from('profiles').select('*').eq('id', data.user.id).single()
  );

  DB.session = {
    id:           data.user.id,
    email:        data.user.email,
    nome:         profile.nome,
    username:     profile.username,
    role:         profile.role,
    workspace_id: profile.workspace_id,
  };

  await carregarTudo();
  return DB.session;
}

/** Logout */
async function sbLogout() {
  await db.auth.signOut();
  DB.session = null;
}

/** Verifica sessão existente ao carregar a página */
async function sbVerificarSessao() {
  const { data: { session } } = await db.auth.getSession();
  if (!session) return null;

  const profile = await handle(
    db.from('profiles').select('*').eq('id', session.user.id).single()
  );
  DB.session = {
    id:           session.user.id,
    email:        session.user.email,
    nome:         profile.nome,
    username:     profile.username,
    role:         profile.role,
    workspace_id: profile.workspace_id,
  };
  await carregarTudo();
  return DB.session;
}

/** Registrar nova oficina (cria workspace + usuário admin) */
async function sbRegistrar(email, senha, nomeOficina, nomeUsuario, username) {
  // 1. Criar o usuário no Supabase Auth
  const { data, error } = await db.auth.signUp({ email, password: senha });
  if (error) throw error;
  if (!data.user) throw new Error('Erro ao criar usuário — tente novamente.');

  // 2. Se o signUp não criou sessão automática (ex: e-mail não confirmado),
  //    fazemos login explícito para ter uma sessão JWT válida.
  if (!data.session) {
    const { data: loginData, error: loginErr } = await db.auth.signInWithPassword({ email, password: senha });
    if (loginErr) throw new Error('Conta criada mas login falhou. Desative "Confirm email" no Dashboard Supabase → Auth → Providers → Email, ou confirme seu e-mail e faça login manualmente.');
  }

  // 3. Chamar RPC para criar workspace + profile
  const slug = nomeOficina.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const newWsId = await handle(
    db.rpc('criar_workspace', {
      p_user_id:   data.user.id,
      p_nome:      nomeOficina,
      p_slug:      slug + '-' + Date.now(),
      p_user_nome: nomeUsuario,
      p_username:  username,
    })
  );
  return newWsId;
}

// ─── CARREGAMENTO INICIAL ─────────────────────────────────────

async function carregarTudo() {
  const wid = wsId();

  const [
    colabs, veiculos, pagamentos, clientes, agenda,
    estoque, auditoria, metas, fila, parcelas,
    notas, satisf, lancamentos, categorias, config, users,
  ] = await Promise.all([
    handle(db.from('colaboradores').select('*').eq('workspace_id', wid).eq('ativo', true)),
    handle(db.from('veiculos').select('*, orcamento_itens(*)').eq('workspace_id', wid)),
    handle(db.from('pagamentos').select('*').eq('workspace_id', wid).order('data', { ascending: false })),
    handle(db.from('clientes').select('*').eq('workspace_id', wid).order('nome')),
    handle(db.from('agenda').select('*').eq('workspace_id', wid)),
    handle(db.from('estoque').select('*').eq('workspace_id', wid)),
    handle(db.from('auditoria').select('*').eq('workspace_id', wid).order('criado_em', { ascending: false }).limit(200)),
    handle(db.from('metas').select('*').eq('workspace_id', wid)),
    handle(db.from('fila').select('*').eq('workspace_id', wid).order('prioridade', { ascending: false })),
    handle(db.from('parcelas').select('*').eq('workspace_id', wid)),
    handle(db.from('notas').select('*').eq('workspace_id', wid)),
    handle(db.from('satisfacoes').select('*').eq('workspace_id', wid)),
    handle(db.from('lancamentos').select('*').eq('workspace_id', wid).order('data', { ascending: false })),
    handle(db.from('categorias_financeiras').select('*').eq('workspace_id', wid)),
    handle(db.from('config').select('*').eq('workspace_id', wid).single()),
    handle(db.from('profiles').select('*').eq('workspace_id', wid)),
  ]);

  DB.colabs     = colabs;
  DB.veiculos   = veiculos.map(veiculoDoDb);
  DB.pagamentos = pagamentos;
  DB.clientes   = clientes;
  DB.agenda     = agenda;
  DB.estoque    = estoque;
  DB.auditoria  = auditoria;
  DB.fila       = fila;
  DB.parcelas   = parcelas;
  DB.notas      = notas;
  DB.satisf     = satisf;
  DB.lancamentos = lancamentos;
  DB.config     = config?.dados || {};
  DB.config.nome = config?.nome_oficina || 'Minha Oficina';
  DB.users      = users;

  // Metas: transformar de array em objeto { 'AAAA-MM': {...} }
  DB.metas = {};
  for (const m of metas) {
    DB.metas[`${m.ano}-${String(m.mes).padStart(2,'0')}`] = m;
  }

  // Categorias
  DB.categorias.entrada = categorias.filter(c => c.tipo === 'entrada').map(c => c.nome);
  DB.categorias.saida   = categorias.filter(c => c.tipo === 'saida').map(c => c.nome);

  // Fotos: objeto { veiculo_id: [url, ...] }
  const fotosArr = await handle(db.from('fotos').select('*').eq('workspace_id', wid));
  DB.fotos = {};
  for (const f of fotosArr) {
    if (!DB.fotos[f.veiculo_id]) DB.fotos[f.veiculo_id] = [];
    DB.fotos[f.veiculo_id].push(f.url || f.storage_path);
  }
}

// ─── VEÍCULOS / ORDENS DE SERVIÇO ────────────────────────────

// Status válidos no CHECK do schema.
const STATUS_VALIDOS = new Set([
  'aguardando','em-andamento','aguardando-pecas','pronto','entregue','cancelado'
]);

const soDigitos = s => (s || '').toString().replace(/\D/g, '');

// Combina data (YYYY-MM-DD) + hora (HH:MM) em ISO no fuso local.
function combinarDataHora(data, hora) {
  if (!data) return null;
  const h = (hora && /^\d{1,2}:\d{2}$/.test(hora)) ? hora : '00:00';
  const d = new Date(`${data}T${h}:00`);
  return isNaN(d) ? null : d.toISOString();
}

// Separa um timestamptz ISO em { data: 'YYYY-MM-DD', hora: 'HH:MM' } no fuso local.
function separarDataHora(iso) {
  if (!iso) return { data: null, hora: null };
  const d = new Date(iso);
  if (isNaN(d)) return { data: null, hora: null };
  const pad = n => String(n).padStart(2, '0');
  return {
    data: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    hora: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
  };
}

// UI → DB. Devolve apenas colunas reais de `veiculos`.
function veiculoParaDb(v) {
  const status = STATUS_VALIDOS.has(v.kanbanStatus) ? v.kanbanStatus
               : STATUS_VALIDOS.has(v.status)       ? v.status
               : 'aguardando';

  const entrada_em = v.entrada_em
    || combinarDataHora(v.dataEntrada, v.horaEntrada)
    || v.timestampEntrada
    || null;

  const saida_em = v.saida_em
    || (v.saida ? combinarDataHora(v.saida.data, v.saida.hora) : null);

  const valor_final = v.valor_final ?? v.saida?.valor ?? null;

  // Tudo que não tem coluna vai para `meta`.
  const meta = {
    telefone:        v.telefone || null,
    cliente_nome:    v.cliente || null,        // fallback p/ leitura sem JOIN
    registradoPor:   v.registradoPor || null,
    timestampEntrada:v.timestampEntrada || null,
    orcamentoStatus: v.orcamentoStatus || null,
    tempoTrabalhado: v.tempoTrabalhado || 0,
    vistoria:        v.vistoria || null,
    saidaPor:        v.saida?.registradoPor || null,
  };

  return {
    id:                v.id && !v.id.toString().startsWith('tmp_') ? v.id : undefined,
    cliente_id:        v.cliente_id || null,
    placa:             v.placa || null,
    modelo:            v.modelo || null,
    cor:               v.cor || null,
    ano:               v.ano || null,
    km:                v.km ?? null,
    servico:           v.servico || null,
    descricao:         v.descricao || null,
    status,
    responsavel_id:    v.responsavel_id || v.mecanicoId || null,
    valor_orcamento:   v.valor_orcamento ?? v.orcamento ?? null,
    valor_final,
    nivel_combustivel: v.nivel_combustivel ?? v.vistoria?.nivel ?? null,
    entrada_em,
    saida_em,
    prazo:             v.prazo || null,
    nota_numero:       v.nota_numero ?? null,
    fc_lanc_id:        v.fc_lanc_id || null,
    meta,
  };
}

// DB → UI. Mantém o shape que oficina-manager-v4.html espera.
function veiculoDoDb(row) {
  const ent = separarDataHora(row.entrada_em);
  const sai = separarDataHora(row.saida_em);
  const meta = row.meta || {};

  // Achar nome do cliente: relação carregada > meta.cliente_nome > cache local.
  const clienteRel = row.clientes;  // se PostgREST trouxer o JOIN
  const clienteCache = (DB.clientes || []).find(c => c.id === row.cliente_id);
  const clienteNome = clienteRel?.nome || clienteCache?.nome || meta.cliente_nome || '';
  const telefone    = clienteRel?.telefone || clienteCache?.telefone || meta.telefone || '';

  return {
    ...row,
    itens:           row.orcamento_itens || [],
    cliente:         clienteNome,
    telefone,
    mecanicoId:      row.responsavel_id || null,
    orcamento:       row.valor_orcamento ?? 0,
    kanbanStatus:    row.status,
    dataEntrada:     ent.data,
    horaEntrada:     ent.hora,
    timestampEntrada:meta.timestampEntrada || row.entrada_em,
    registradoPor:   meta.registradoPor || '',
    orcamentoStatus: meta.orcamentoStatus || null,
    tempoTrabalhado: meta.tempoTrabalhado || 0,
    vistoria:        meta.vistoria || null,
    saida: row.saida_em ? {
      data:          sai.data,
      hora:          sai.hora,
      valor:         row.valor_final ?? 0,
      registradoPor: meta.saidaPor || '',
    } : null,
  };
}

// Resolve cliente: procura no cache por telefone (digitos) ou nome.
// Cria se não existir. Devolve o uuid.
async function sbResolverCliente({ nome, telefone }) {
  if (!nome && !telefone) return null;
  const telDigitos = soDigitos(telefone);

  let achado = null;
  if (telDigitos) {
    achado = (DB.clientes || []).find(c => soDigitos(c.telefone) === telDigitos);
  }
  if (!achado && nome) {
    const n = nome.trim().toLowerCase();
    achado = (DB.clientes || []).find(c => (c.nome || '').trim().toLowerCase() === n);
  }
  if (achado) return achado.id;

  // Não existe → cria.
  const novo = await handle(
    db.from('clientes').insert({
      workspace_id: wsId(),
      nome:         nome || 'Sem nome',
      telefone:     telefone || null,
    }).select().single()
  );
  DB.clientes = [novo, ...(DB.clientes || [])];
  return novo.id;
}

async function sbSalvarVeiculo(veiculo) {
  // 1. Resolver cliente_id se ainda não tiver.
  if (!veiculo.cliente_id && (veiculo.cliente || veiculo.telefone)) {
    veiculo.cliente_id = await sbResolverCliente({
      nome:     veiculo.cliente,
      telefone: veiculo.telefone,
    });
  }

  // 2. Mapear UI → colunas reais.
  const row = veiculoParaDb(veiculo);
  row.workspace_id = wsId();

  let saved;
  if (row.id) {
    saved = await handle(
      db.from('veiculos').update(row).eq('id', row.id).select().single()
    );
  } else {
    delete row.id;
    saved = await handle(
      db.from('veiculos').insert(row).select().single()
    );
  }
  const savedId = saved.id;

  // 3. Salvar itens do orçamento (tabela separada).
  const itens = veiculo.itens || veiculo.orcamento_itens;
  if (Array.isArray(itens)) {
    await handle(db.from('orcamento_itens').delete().eq('veiculo_id', savedId));
    if (itens.length > 0) {
      await handle(
        db.from('orcamento_itens').insert(
          itens.map((it, i) => ({
            veiculo_id:   savedId,
            workspace_id: wsId(),
            descricao:    it.descricao || it.desc || '',
            quantidade:   it.quantidade || it.qtd || 1,
            preco_unit:   it.preco_unit || it.preco || ((it.mo || 0) + (it.pecas || 0)),
            ordem:        i,
          }))
        )
      );
    }
  }

  return savedId;
}

async function sbExcluirVeiculo(id) {
  await handle(db.from('veiculos').delete().eq('id', id));
}

async function sbMoverKanban(id, novoStatus) {
  await handle(db.from('veiculos').update({ status: novoStatus }).eq('id', id));
}

// ─── CLIENTES ─────────────────────────────────────────────────

async function sbSalvarCliente(cliente) {
  const row = { ...cliente, workspace_id: wsId() };
  if (row.id) {
    return handle(db.from('clientes').update(row).eq('id', row.id).select().single());
  }
  delete row.id;
  return handle(db.from('clientes').insert(row).select().single());
}

async function sbExcluirCliente(id) {
  await handle(db.from('clientes').delete().eq('id', id));
}

// ─── COLABORADORES ────────────────────────────────────────────

async function sbSalvarColab(colab) {
  const row = { ...colab, workspace_id: wsId() };
  if (row.id) {
    return handle(db.from('colaboradores').update(row).eq('id', row.id).select().single());
  }
  delete row.id;
  return handle(db.from('colaboradores').insert(row).select().single());
}

async function sbExcluirColab(id) {
  await handle(db.from('colaboradores').update({ ativo: false }).eq('id', id));
}

// ─── ESTOQUE ─────────────────────────────────────────────────

async function sbSalvarEstoque(item) {
  const row = { ...item, workspace_id: wsId() };
  if (row.id) {
    return handle(db.from('estoque').update(row).eq('id', row.id).select().single());
  }
  delete row.id;
  return handle(db.from('estoque').insert(row).select().single());
}

async function sbAjustarEstoque(id, delta) {
  await handle(
    db.rpc('ajustar_estoque', { p_id: id, p_delta: delta })
  );
}

// ─── PAGAMENTOS / CAIXA ───────────────────────────────────────

async function sbSalvarPagamento(pag) {
  const row = { ...pag, workspace_id: wsId() };
  delete row.id;
  return handle(db.from('pagamentos').insert(row).select().single());
}

// ─── LANÇAMENTOS (FinControl) ─────────────────────────────────

async function sbSalvarLancamento(lanc) {
  const row = { ...lanc, workspace_id: wsId() };
  delete row.id;
  return handle(db.from('lancamentos').insert(row).select().single());
}

// ─── AGENDA ───────────────────────────────────────────────────

async function sbSalvarAgenda(evento) {
  const row = { ...evento, workspace_id: wsId() };
  if (row.id) {
    return handle(db.from('agenda').update(row).eq('id', row.id).select().single());
  }
  delete row.id;
  return handle(db.from('agenda').insert(row).select().single());
}

async function sbExcluirAgenda(id) {
  await handle(db.from('agenda').delete().eq('id', id));
}

// ─── PARCELAS ─────────────────────────────────────────────────

async function sbSalvarParcela(parcela) {
  const row = { ...parcela, workspace_id: wsId() };
  if (row.id) {
    return handle(db.from('parcelas').update(row).eq('id', row.id).select().single());
  }
  delete row.id;
  return handle(db.from('parcelas').insert(row).select().single());
}

async function sbPagarParcela(id) {
  return handle(
    db.from('parcelas').update({ pago: true, pago_em: new Date().toISOString() }).eq('id', id).select().single()
  );
}

// ─── AUDITORIA ────────────────────────────────────────────────

async function sbLogAudit(acao, detalhe) {
  if (!DB.session) return;
  await handle(
    db.from('auditoria').insert({
      workspace_id: wsId(),
      user_id:      DB.session.id,
      username:     DB.session.username,
      acao,
      detalhe,
    })
  );
}

// ─── CONFIG ───────────────────────────────────────────────────

async function sbSalvarConfig(novoConfig) {
  const { nome, ...dados } = novoConfig;
  await handle(
    db.from('config').upsert({
      workspace_id:  wsId(),
      nome_oficina:  nome || 'Minha Oficina',
      dados,
    })
  );
  DB.config = novoConfig;
}

// ─── USUÁRIOS DO WORKSPACE ────────────────────────────────────

async function sbConvidarUsuario(email, nomeUsuario, username, role) {
  // 1. Cria o usuário via Admin API (precisa de Edge Function ou service role)
  // Na prática, envie o link de convite por e-mail com signInWithOtp ou invite link.
  // Aqui usamos a abordagem de "magic link".
  const { error } = await db.auth.admin.inviteUserByEmail(email);
  if (error) throw error;
  // O perfil será criado no webhook de confirmação de e-mail (ver supabase/functions/on-signup.ts)
}

async function sbAlterarRoleUsuario(userId, novoRole) {
  await handle(
    db.from('profiles')
      .update({ role: novoRole })
      .eq('id', userId)
      .eq('workspace_id', wsId())
  );
}

// ─── REALTIME ─────────────────────────────────────────────────
// Chame `sbInscreverRealtime(onUpdate)` após login.
// `onUpdate(tabela, evento, registro)` é chamado quando qualquer cliente
// modifica os dados, permitindo atualizar o estado local e o DOM.

function sbInscreverRealtime(onUpdate) {
  const wid = wsId();
  const tabelas = ['veiculos', 'pagamentos', 'estoque', 'agenda', 'fila', 'notas'];

  tabelas.forEach(tabela => {
    db.channel(`realtime:${tabela}:${wid}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: tabela, filter: `workspace_id=eq.${wid}` },
        payload => {
          aplicarMudancaLocal(tabela, payload.eventType, payload.new || payload.old);
          onUpdate(tabela, payload.eventType, payload.new || payload.old);
        }
      )
      .subscribe();
  });
}

function aplicarMudancaLocal(tabela, evento, registro) {
  const mapa = {
    veiculos:   'veiculos',
    pagamentos: 'pagamentos',
    estoque:    'estoque',
    agenda:     'agenda',
    fila:       'fila',
    notas:      'notas',
  };
  const chave = mapa[tabela];
  if (!chave) return;

  // Para `veiculos`, o payload do realtime vem em snake_case do Postgres
  // — precisa passar pelo mapper para a UI continuar enxergando dataEntrada,
  // kanbanStatus, cliente, etc.
  const normaliza = (tabela === 'veiculos' && registro?.id)
    ? veiculoDoDb(registro)
    : registro;

  if (evento === 'INSERT') {
    DB[chave] = [normaliza, ...DB[chave]];
  } else if (evento === 'UPDATE') {
    DB[chave] = DB[chave].map(r => r.id === normaliza.id ? { ...r, ...normaliza } : r);
  } else if (evento === 'DELETE') {
    DB[chave] = DB[chave].filter(r => r.id !== registro.id);
  }
}

// ─── FOTOS (Supabase Storage) ─────────────────────────────────

async function sbUploadFoto(veiculoId, file) {
  const path = `${wsId()}/${veiculoId}/${Date.now()}-${file.name}`;
  await handle(db.storage.from('fotos').upload(path, file));

  const { data: { publicUrl } } = db.storage.from('fotos').getPublicUrl(path);

  await handle(
    db.from('fotos').insert({
      veiculo_id:   veiculoId,
      workspace_id: wsId(),
      storage_path: path,
      url:          publicUrl,
    })
  );

  if (!DB.fotos[veiculoId]) DB.fotos[veiculoId] = [];
  DB.fotos[veiculoId].push(publicUrl);
  return publicUrl;
}

// ─── MIGRAÇÃO LocalStorage → Supabase ────────────────────────
// Execute uma única vez em um navegador que tenha dados legados.
// Ver migration-script.js para uso completo.

async function migrarLocalStorage() {
  const K = {
    colabs:    'om_colabs',
    veiculos:  'om_veiculos',
    pagamentos:'om_pagamentos',
    clientes:  'om_clientes',
    agenda:    'om_agenda',
    estoque:   'om_estoque',
    lanc:      'fc_lancamentos',
  };

  async function importar(chave, tabela, transform) {
    const raw = localStorage.getItem(K[chave]);
    if (!raw) return;
    const items = JSON.parse(raw);
    if (!items.length) return;
    const rows = items.map(it => ({ ...transform(it), workspace_id: wsId() }));
    await handle(db.from(tabela).upsert(rows, { onConflict: 'id' }));
    console.log(`[Migração] ${rows.length} registros importados para ${tabela}`);
  }

  await importar('clientes',  'clientes',  c => ({ nome: c.nome, telefone: c.tel||c.telefone, email: c.email, obs: c.obs }));
  await importar('colabs',    'colaboradores', c => ({ nome: c.nome, funcao: c.funcao, salario: c.salario, comissao_pct: c.comissao||0, telefone: c.tel||c.telefone }));
  await importar('estoque',   'estoque',   e => ({ nome: e.nome, quantidade: e.qtd||e.quantidade||0, unidade: e.un||e.unidade||'un', preco_custo: e.preco, estoque_min: e.min||0 }));
  await importar('pagamentos','pagamentos',p => ({ tipo: p.tipo, descricao: p.desc||p.descricao, valor: p.valor, data: p.data || new Date().toISOString().slice(0,10) }));
  await importar('lanc',      'lancamentos', l => ({ tipo: l.tipo, descricao: l.desc||l.descricao, valor: l.valor, categoria: l.cat, data: l.data || new Date().toISOString().slice(0,10) }));

  console.log('[Migração] Concluída!');
}
