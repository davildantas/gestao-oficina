-- =====================================================================
-- Migration: Melhorias OficinaManager
-- Data: 2026-05-13
-- Inclui:
--   (1) Tabela materiais_os (Task 3 — Materiais por OS)
--   (2) Colunas extras em colaboradores (Task 5 — Funcionários completos)
-- =====================================================================

-- ---------------------------------------------------------------------
-- TASK 3 — Materiais consumidos por OS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS materiais_os (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  veiculo_id      uuid NOT NULL REFERENCES veiculos(id) ON DELETE CASCADE,
  estoque_id      uuid REFERENCES estoque(id),
  nome            text NOT NULL,
  quantidade      numeric NOT NULL DEFAULT 1,
  preco_unit      numeric DEFAULT 0,
  total           numeric GENERATED ALWAYS AS (quantidade * preco_unit) STORED,
  observacao      text,
  retirado_por    text,
  retirado_em     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_materiais_os_veiculo   ON materiais_os(veiculo_id);
CREATE INDEX IF NOT EXISTS idx_materiais_os_workspace ON materiais_os(workspace_id);

ALTER TABLE materiais_os ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "materiais_os_workspace_policy" ON materiais_os;
CREATE POLICY "materiais_os_workspace_policy" ON materiais_os
  FOR ALL
  USING  (workspace_id = (SELECT workspace_id FROM profiles WHERE id = auth.uid()))
  WITH CHECK (workspace_id = (SELECT workspace_id FROM profiles WHERE id = auth.uid()));

-- ---------------------------------------------------------------------
-- TASK 5 — Dados pessoais completos do colaborador
-- ---------------------------------------------------------------------
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS cpf                  text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS rg                   text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS rg_orgao             text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS rg_uf                text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS data_nascimento      date;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS naturalidade         text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS nacionalidade        text DEFAULT 'Brasileiro';
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS estado_civil         text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS nome_mae             text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS nome_pai             text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS telefone_fixo        text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS email_pessoal        text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS email_corp           text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS cep                  text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS logradouro           text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS numero_end           text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS complemento          text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS bairro               text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS cidade               text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS estado_uf            text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS banco                text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS tipo_conta           text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS agencia              text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS conta_bancaria       text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS pix_tipo             text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS data_admissao        date;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS ctps                 text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS ctps_serie           text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS ctps_uf              text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS pis_pasep            text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS data_desligamento    date;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS motivo_desligamento  text;
ALTER TABLE colaboradores ADD COLUMN IF NOT EXISTS docs_status          jsonb DEFAULT '{}'::jsonb;

-- ---------------------------------------------------------------------
-- Realtime — opcional, adicionar materiais_os ao broadcast
-- ---------------------------------------------------------------------
DO $$ BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE materiais_os;
  EXCEPTION WHEN duplicate_object THEN
    -- já está na publicação
    NULL;
  END;
END $$;
