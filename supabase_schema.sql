-- ═══════════════════════════════════════════════════════════
-- TÚLIO PARCA HUB — Schema Supabase (RLS reforçado)
-- Execute todo este arquivo no SQL Editor do Supabase
-- (cole o conteúdo e clique em "Run"). Pode rodar novamente
-- sem problema: as políticas antigas são substituídas.
-- ═══════════════════════════════════════════════════════════

-- ─── 1. PROFILES (vinculada ao auth.users) ───────────────
CREATE TABLE IF NOT EXISTS profiles (
  id         UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  nome       TEXT NOT NULL,
  funcao     TEXT NOT NULL DEFAULT 'colaborador',  -- 'socio' | 'colaborador'
  ativo      BOOLEAN NOT NULL DEFAULT FALSE,
  colab_id   UUID,
  criado_em  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 2. COLABORADORES ────────────────────────────────────
CREATE TABLE IF NOT EXISTS colaboradores (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nome      TEXT NOT NULL,
  email     TEXT,
  cargo     TEXT,
  area      TEXT,
  telefone  TEXT,
  admissao  TEXT,
  obs       TEXT,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 3. TAREFAS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tarefas (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  colab_id       UUID REFERENCES colaboradores(id) ON DELETE CASCADE,
  periodo        TEXT NOT NULL CHECK (periodo IN ('diario','semanal','mensal')),
  descricao      TEXT NOT NULL,
  frequencia     TEXT DEFAULT 'diaria',
  intervalo_dias INTEGER,
  data_inicio    TEXT,
  data_fim       TEXT,
  ordem          INTEGER DEFAULT 0,
  criado_em      TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 4. CHECKINS ─────────────────────────────────────────
-- bucket: chave de período, ex: 'D20260531', 'S2026_22', 'M202605'
CREATE TABLE IF NOT EXISTS checkins (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tarefa_id UUID REFERENCES tarefas(id) ON DELETE CASCADE,
  colab_id  UUID REFERENCES colaboradores(id) ON DELETE CASCADE,
  bucket    TEXT NOT NULL,
  concluido BOOLEAN DEFAULT TRUE,
  criado_em TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (tarefa_id, colab_id, bucket)
);

-- ═══════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES (SECURITY DEFINER evita recursão no RLS)
-- ═══════════════════════════════════════════════════════════

-- O usuário logado é um sócio ativo?
CREATE OR REPLACE FUNCTION public.is_socio()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND funcao = 'socio' AND ativo = TRUE
  );
$$;

-- Qual o colab_id ligado ao usuário logado?
CREATE OR REPLACE FUNCTION public.meu_colab_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT colab_id FROM public.profiles WHERE id = auth.uid();
$$;

-- ═══════════════════════════════════════════════════════════
-- TRIGGER: ao cadastrar usuário, cria o profile e (se for
-- colaborador) já cria o registro em colaboradores e vincula.
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_funcao    TEXT;
  v_nome      TEXT;
  v_ativo     BOOLEAN;
  v_has_socio BOOLEAN;
  v_colab_id  UUID := NULL;
BEGIN
  v_funcao := COALESCE(NEW.raw_user_meta_data->>'funcao', 'colaborador');
  v_nome   := COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1));

  SELECT EXISTS(
    SELECT 1 FROM public.profiles WHERE funcao = 'socio' AND ativo = TRUE
  ) INTO v_has_socio;

  -- Primeiro sócio é aprovado automaticamente; demais aguardam aprovação.
  v_ativo := (v_funcao = 'socio' AND NOT v_has_socio);

  -- Colaborador já ganha um registro em colaboradores (com nome e e-mail).
  IF v_funcao = 'colaborador' THEN
    INSERT INTO public.colaboradores (nome, email)
    VALUES (v_nome, NEW.email)
    RETURNING id INTO v_colab_id;
  END IF;

  INSERT INTO public.profiles (id, nome, funcao, ativo, colab_id)
  VALUES (NEW.id, v_nome, v_funcao, v_ativo, v_colab_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ═══════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) — REFORÇADO
-- Regra geral: cada colaborador só acessa os PRÓPRIOS dados;
-- sócios ativos acessam tudo. A criação de perfis/colaboradores
-- no cadastro é feita pelo trigger acima (que ignora o RLS).
-- ═══════════════════════════════════════════════════════════
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE colaboradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE tarefas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkins      ENABLE ROW LEVEL SECURITY;

-- Remove políticas antigas (caso o schema permissivo já tenha sido aplicado)
DROP POLICY IF EXISTS "autenticado" ON profiles;
DROP POLICY IF EXISTS "autenticado" ON colaboradores;
DROP POLICY IF EXISTS "autenticado" ON tarefas;
DROP POLICY IF EXISTS "autenticado" ON checkins;
DROP POLICY IF EXISTS profiles_select  ON profiles;
DROP POLICY IF EXISTS profiles_update  ON profiles;
DROP POLICY IF EXISTS profiles_delete  ON profiles;
DROP POLICY IF EXISTS colab_select     ON colaboradores;
DROP POLICY IF EXISTS colab_insert     ON colaboradores;
DROP POLICY IF EXISTS colab_update     ON colaboradores;
DROP POLICY IF EXISTS colab_delete     ON colaboradores;
DROP POLICY IF EXISTS tarefas_select   ON tarefas;
DROP POLICY IF EXISTS tarefas_insert   ON tarefas;
DROP POLICY IF EXISTS tarefas_update   ON tarefas;
DROP POLICY IF EXISTS tarefas_delete   ON tarefas;
DROP POLICY IF EXISTS checkins_select  ON checkins;
DROP POLICY IF EXISTS checkins_insert  ON checkins;
DROP POLICY IF EXISTS checkins_update  ON checkins;
DROP POLICY IF EXISTS checkins_delete  ON checkins;

-- ─── PROFILES ────────────────────────────────────────────
-- Ver o próprio perfil OU todos, se for sócio.
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated
  USING ( id = auth.uid() OR is_socio() );
-- Atualizar o próprio perfil OU qualquer um, se for sócio (aprovar/editar).
CREATE POLICY profiles_update ON profiles FOR UPDATE TO authenticated
  USING ( id = auth.uid() OR is_socio() )
  WITH CHECK ( id = auth.uid() OR is_socio() );
-- Excluir: somente sócios.
CREATE POLICY profiles_delete ON profiles FOR DELETE TO authenticated
  USING ( is_socio() );
-- (INSERT em profiles é feito apenas pelo trigger.)

-- ─── COLABORADORES ───────────────────────────────────────
-- Ver o próprio registro OU todos, se for sócio.
CREATE POLICY colab_select ON colaboradores FOR SELECT TO authenticated
  USING ( id = meu_colab_id() OR is_socio() );
-- Criar: somente sócios (no cadastro normal, quem cria é o trigger).
CREATE POLICY colab_insert ON colaboradores FOR INSERT TO authenticated
  WITH CHECK ( is_socio() );
-- Atualizar o próprio registro OU qualquer um, se for sócio.
CREATE POLICY colab_update ON colaboradores FOR UPDATE TO authenticated
  USING ( id = meu_colab_id() OR is_socio() )
  WITH CHECK ( id = meu_colab_id() OR is_socio() );
-- Excluir: somente sócios.
CREATE POLICY colab_delete ON colaboradores FOR DELETE TO authenticated
  USING ( is_socio() );

-- ─── TAREFAS ─────────────────────────────────────────────
-- As próprias tarefas OU todas, se for sócio.
CREATE POLICY tarefas_select ON tarefas FOR SELECT TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY tarefas_insert ON tarefas FOR INSERT TO authenticated
  WITH CHECK ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY tarefas_update ON tarefas FOR UPDATE TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() )
  WITH CHECK ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY tarefas_delete ON tarefas FOR DELETE TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() );

-- ─── CHECKINS ────────────────────────────────────────────
-- As próprias marcações OU todas, se for sócio.
CREATE POLICY checkins_select ON checkins FOR SELECT TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY checkins_insert ON checkins FOR INSERT TO authenticated
  WITH CHECK ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY checkins_update ON checkins FOR UPDATE TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() )
  WITH CHECK ( colab_id = meu_colab_id() OR is_socio() );
CREATE POLICY checkins_delete ON checkins FOR DELETE TO authenticated
  USING ( colab_id = meu_colab_id() OR is_socio() );

-- ═══════════════════════════════════════════════════════════
-- CONFIGURAÇÃO OBRIGATÓRIA NO PAINEL DO SUPABASE:
--
-- 1. Authentication → Providers → Email
--    ☑ Desabilitar "Confirm email" (Enable email confirmations = OFF)
--    Isso permite login imediato após cadastro, sem link de e-mail.
--
-- 2. Authentication → URL Configuration
--    Site URL: cole a URL do seu projeto (ex: Vercel/Netlify)
--    ex: https://tp-hub-rotinas.vercel.app
--
-- 3. Para tornar alguém sócio manualmente (se precisar), rode:
--    UPDATE profiles SET funcao='socio', ativo=TRUE
--    WHERE id = (SELECT id FROM auth.users WHERE email='voce@tulioparca.com.br');
-- ═══════════════════════════════════════════════════════════
