// =============================================================
// SCRIPT DE MIGRAÇÃO — localStorage → Supabase
// =============================================================
// Execute este script UMA VEZ em um navegador que tenha os dados
// do sistema antigo. Acesse o console do navegador e chame:
//
//   await migrarTudo()
//
// Pré-requisitos:
//   1. Usuário já logado no novo sistema (sbLogin já chamado)
//   2. client.js carregado na página
// =============================================================

async function migrarTudo() {
  console.group('🚀 Migração LocalStorage → Supabase');

  const wid = DB.session?.workspace_id;
  if (!wid) { console.error('Faça login primeiro'); return; }

  // ── helpers ────────────────────────────────────────────────
  const ler = k => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch { return null; } };

  async function upsert(tabela, rows) {
    if (!rows?.length) return 0;
    const { error } = await db.from(tabela).upsert(rows, { ignoreDuplicates: true });
    if (error) { console.error(`  ERRO em ${tabela}:`, error.message); return 0; }
    console.log(`  ✓ ${tabela}: ${rows.length} registros`);
    return rows.length;
  }

  // ── clientes ───────────────────────────────────────────────
  const clientes = (ler('om_clientes') || []).map(c => ({
    nome:         c.nome || '(sem nome)',
    telefone:     c.tel || c.telefone || null,
    email:        c.email || null,
    cpf_cnpj:     c.cpf || c.cnpj || null,
    endereco:     c.endereco || null,
    obs:          c.obs || null,
    workspace_id: wid,
  }));
  await upsert('clientes', clientes);

  // Recarrega clientes para ter IDs reais (usaremos nos próximos passos)
  const { data: clientesSalvos } = await db.from('clientes').select('id,nome,telefone').eq('workspace_id', wid);

  function matchCliente(nome, tel) {
    return clientesSalvos?.find(c =>
      c.nome === nome || (tel && c.telefone === tel)
    )?.id || null;
  }

  // ── colaboradores ──────────────────────────────────────────
  const colabs = (ler('om_colabs') || []).map(c => ({
    nome:          c.nome || '(sem nome)',
    funcao:        c.funcao || null,
    salario:       Number(c.salario) || 0,
    comissao_pct:  Number(c.comissao) || 0,
    telefone:      c.tel || c.telefone || null,
    ativo:         c.ativo !== false,
    workspace_id:  wid,
  }));
  await upsert('colaboradores', colabs);

  // ── estoque ────────────────────────────────────────────────
  const estoque = (ler('om_estoque') || []).map(e => ({
    nome:          e.nome || '(sem nome)',
    quantidade:    Number(e.qtd || e.quantidade) || 0,
    unidade:       e.un || e.unidade || 'un',
    preco_custo:   Number(e.preco || e.preco_custo) || null,
    estoque_min:   Number(e.min || e.estoque_min) || 0,
    categoria:     e.cat || e.categoria || null,
    workspace_id:  wid,
  }));
  await upsert('estoque', estoque);

  // ── veículos / OSs ─────────────────────────────────────────
  const veiculosRaw = ler('om_veiculos') || [];
  const veiculosMapped = veiculosRaw.map(v => ({
    placa:            v.placa || null,
    modelo:           v.modelo || null,
    cor:              v.cor || null,
    ano:              v.ano ? String(v.ano) : null,
    km:               Number(v.km) || null,
    servico:          v.servico || null,
    descricao:        v.desc || v.descricao || null,
    status:           v.status || 'aguardando',
    valor_orcamento:  Number(v.orcamento || v.valor_orcamento) || null,
    valor_final:      Number(v.valorFinal || v.valor_final) || null,
    nivel_combustivel:Number(v.combustivel || v.nivel_combustivel) || null,
    entrada_em:       v.entrada || v.entrada_em || null,
    saida_em:         v.saida?.data || v.saida_em || null,
    prazo:            v.prazo || null,
    cliente_id:       matchCliente(v.cliente, v.tel),
    workspace_id:     wid,
    _old_id:          v.id,  // para mapear itens
  }));

  // Insere veículos um a um para capturar IDs
  const veiculoIdMap = {};
  for (const v of veiculosMapped) {
    const { _old_id, ...row } = v;
    const { data, error } = await db.from('veiculos').insert(row).select('id').single();
    if (error) { console.warn('  ! veículo ignorado:', error.message); continue; }
    veiculoIdMap[_old_id] = data.id;
  }
  console.log(`  ✓ veiculos: ${Object.keys(veiculoIdMap).length} registros`);

  // Itens de orçamento
  const orcItens = [];
  for (const v of veiculosRaw) {
    const newId = veiculoIdMap[v.id];
    if (!newId) continue;
    const itens = v.itens || v.orcamento || [];
    itens.forEach((it, i) => {
      orcItens.push({
        veiculo_id:   newId,
        workspace_id: wid,
        descricao:    it.descricao || it.desc || '',
        quantidade:   Number(it.qtd || it.quantidade) || 1,
        preco_unit:   Number(it.preco || it.preco_unit) || 0,
        ordem:        i,
      });
    });
  }
  await upsert('orcamento_itens', orcItens);

  // ── agenda ─────────────────────────────────────────────────
  const agenda = (ler('om_agenda') || []).map(a => ({
    titulo:       a.titulo || a.desc || '(sem título)',
    data:         a.data || new Date().toISOString().slice(0,10),
    hora:         a.hora || null,
    tipo:         a.tipo || null,
    obs:          a.obs || null,
    workspace_id: wid,
  }));
  await upsert('agenda', agenda);

  // ── pagamentos ─────────────────────────────────────────────
  const pagamentos = (ler('om_pagamentos') || []).map(p => ({
    tipo:         p.tipo === 'entrada' ? 'entrada' : 'saida',
    descricao:    p.desc || p.descricao || '',
    valor:        Number(p.valor) || 0,
    forma:        p.forma || null,
    categoria:    p.cat || p.categoria || null,
    data:         p.data || new Date().toISOString().slice(0,10),
    obs:          p.obs || null,
    workspace_id: wid,
  }));
  await upsert('pagamentos', pagamentos);

  // ── lançamentos financeiros (FinControl) ───────────────────
  const lanc = (ler('fc_lancamentos') || []).map(l => ({
    tipo:         l.tipo === 'entrada' ? 'entrada' : 'saida',
    descricao:    l.desc || l.descricao || '',
    valor:        Number(l.valor) || 0,
    categoria:    l.cat || l.categoria || null,
    data:         l.data || new Date().toISOString().slice(0,10),
    obs:          l.obs || null,
    workspace_id: wid,
  }));
  await upsert('lancamentos', lanc);

  // ── categorias financeiras ─────────────────────────────────
  const cats = ler('fc_cats');
  if (cats) {
    const catRows = [];
    (cats.entrada || []).forEach(n => catRows.push({ workspace_id: wid, tipo: 'entrada', nome: n }));
    (cats.saida   || []).forEach(n => catRows.push({ workspace_id: wid, tipo: 'saida',   nome: n }));
    if (catRows.length) {
      const { error } = await db.from('categorias_financeiras').upsert(catRows, { onConflict: 'workspace_id,tipo,nome', ignoreDuplicates: true });
      if (!error) console.log(`  ✓ categorias_financeiras: ${catRows.length} registros`);
    }
  }

  // ── config ─────────────────────────────────────────────────
  const cfg = ler('om_config');
  if (cfg) {
    const { nome, catSalario, catServico, catPecas, ...resto } = cfg;
    await db.from('config').upsert({
      workspace_id: wid,
      nome_oficina: nome || 'Minha Oficina',
      cat_servico:  catServico || 'Serviços',
      cat_pecas:    catPecas || 'Compra de peças',
      cat_salario:  catSalario || 'Folha de pagamento',
      dados:        resto,
    });
    console.log('  ✓ config migrada');
  }

  // ── satisfações ────────────────────────────────────────────
  const satisf = (ler('om_satisfacoes') || []).map(s => ({
    nota:         Number(s.nota) || 3,
    comentario:   s.obs || s.comentario || null,
    workspace_id: wid,
  }));
  await upsert('satisfacoes', satisf);

  // ── notas ──────────────────────────────────────────────────
  const notas = (ler('om_notas') || []).map(n => ({
    texto:        n.texto || n.text || '',
    workspace_id: wid,
  }));
  await upsert('notas', notas);

  console.log('');
  console.log('✅ Migração concluída! Recarregue a página.');
  console.groupEnd();
}
