-- =====================================================================
-- Migration: Kanban — novos status de etapa
-- Data: 2026-06-05
-- Motivo:
--   O Kanban passou a ter as etapas Preparação, Pintura e Polimento.
--   A constraint CHECK de veiculos.status só permitia os status antigos,
--   então mover um card para uma etapa nova estourava:
--     new row for relation "veiculos" violates check constraint
--     "veiculos_status_check"
--   Esta migration recria a constraint com a lista completa de status.
--
-- Robusto contra schema drift (a constraint pode ter sido renomeada em
-- produção): remove qualquer CHECK de status existente antes de recriar.
-- =====================================================================

do $$
declare c record;
begin
  -- remove toda constraint CHECK da tabela veiculos cujo texto referencie
  -- o status 'aguardando' (i.e., a verificação da coluna status)
  for c in
    select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
     where nsp.nspname = 'public'
       and rel.relname = 'veiculos'
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%aguardando%'
  loop
    execute format('alter table public.veiculos drop constraint %I', c.conname);
  end loop;
end $$;

-- recria com a lista completa de etapas do Kanban
alter table public.veiculos
  add constraint veiculos_status_check
  check (status in (
    'aguardando',
    'aguardando-pecas',
    'em-andamento',
    'preparacao',
    'pintura',
    'polimento',
    'pronto',
    'entregue',
    'cancelado'
  ));
