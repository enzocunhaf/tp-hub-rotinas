# Guia: Supabase + Hospedagem do Hub de Rotinas
## Túlio Parca Advogados

---

## PARTE 1 — Integração com Supabase (banco de dados compartilhado)

### Por que Supabase?
O hub atual salva dados apenas no navegador local (localStorage). Com Supabase, todos os colaboradores acessam os mesmos dados em tempo real, de qualquer dispositivo.

---

### Passo 1 — Criar conta e projeto

1. Acesse **https://supabase.com** e crie uma conta gratuita.
2. Clique em **"New Project"**, dê o nome `tulio-parca-hub`.
3. Defina uma senha forte para o banco e escolha a região **South America (São Paulo)**.
4. Aguarde o projeto ser criado (~2 min).

---

### Passo 2 — Criar as tabelas no banco

No painel do Supabase, vá em **SQL Editor** e execute os comandos abaixo:

```sql
-- Tabela de colaboradores
CREATE TABLE colaboradores (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nome        TEXT NOT NULL,
  email       TEXT,
  cargo       TEXT NOT NULL,
  area        TEXT,
  telefone    TEXT,
  admissao    DATE,
  obs         TEXT,
  criado_em   TIMESTAMP DEFAULT NOW()
);

-- Tabela de tarefas dos checklists
CREATE TABLE tarefas (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  colab_id    UUID REFERENCES colaboradores(id) ON DELETE CASCADE,
  periodo     TEXT CHECK (periodo IN ('diario','semanal','mensal')),
  descricao   TEXT NOT NULL,
  ordem       INTEGER DEFAULT 0
);

-- Tabela de registros de conclusão (checkins)
CREATE TABLE checkins (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tarefa_id   UUID REFERENCES tarefas(id) ON DELETE CASCADE,
  colab_id    UUID REFERENCES colaboradores(id) ON DELETE CASCADE,
  data_ref    DATE NOT NULL,   -- data do dia/semana/mês
  concluido   BOOLEAN DEFAULT TRUE,
  criado_em   TIMESTAMP DEFAULT NOW(),
  UNIQUE (tarefa_id, data_ref)
);
```

---

### Passo 3 — Obter as credenciais

1. No painel do Supabase, vá em **Settings → API**.
2. Copie:
   - **Project URL** → ex.: `https://xyzabc.supabase.co`
   - **anon public key** → chave longa começando com `eyJ...`

---

### Passo 4 — Substituir o localStorage no HTML

No arquivo `dashboard_colaboradores.html`, adicione no `<head>` antes do fechamento:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```

E substitua o bloco `// DATA` no JavaScript pelas chamadas ao Supabase:

```javascript
const SUPABASE_URL = 'https://SEU-PROJETO.supabase.co';
const SUPABASE_KEY = 'SUA-ANON-KEY';
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// Carregar colaboradores
async function loadColabs() {
  const { data, error } = await supabase
    .from('colaboradores')
    .select('*, tarefas(*)');
  if (!error) db.colabs = data;
  renderTabela();
}

// Salvar colaborador
async function salvarColab(dados) {
  const { data, error } = await supabase
    .from('colaboradores')
    .insert([dados])
    .select();
  if (!error) db.colabs.push(data[0]);
  renderTabela();
}

// Marcar tarefa concluída
async function marcarConcluido(tarefaId, colabId, dataRef) {
  await supabase.from('checkins').upsert({
    tarefa_id: tarefaId,
    colab_id: colabId,
    data_ref: dataRef,
    concluido: true
  });
}
```

> **Nota:** Se quiser que eu reescreva o HTML completo já integrado ao Supabase, é só pedir. O processo acima é o roteiro — a implementação completa é feita de uma vez.

---

### Passo 5 — Segurança (Row Level Security)

No Supabase, vá em **Authentication → Policies** e ative RLS (Row Level Security) nas tabelas. Isso garante que cada colaborador só leia seus próprios dados. Exemplo de política:

```sql
-- Colaborador só vê suas próprias tarefas
CREATE POLICY "colab_proprio" ON tarefas
  FOR SELECT USING (colab_id = auth.uid());
```

Para os sócios, crie um papel `socio` com acesso total.

---

## PARTE 2 — Transformar em site e hospedar

### Opção A — Netlify (recomendado, gratuito)

É a forma mais simples. O arquivo HTML vira um site em menos de 5 minutos.

1. Acesse **https://netlify.com** e crie uma conta (gratuita).
2. Na dashboard, clique em **"Add new site → Deploy manually"**.
3. Arraste o arquivo `dashboard_colaboradores.html` para a área indicada.
4. O Netlify gera um link como `https://tp-hub-rotinas.netlify.app`.
5. Para personalizar o domínio: vá em **Domain Settings → Add custom domain** e configure `hub.tulioparca.com.br` (requer acesso ao DNS do domínio do escritório).

**Para atualizar:** arraste o novo HTML novamente — o link permanece o mesmo.

---

### Opção B — Vercel (também gratuito)

1. Acesse **https://vercel.com**, crie conta e clique em **"Add New Project"**.
2. Faça upload do arquivo HTML ou conecte a um repositório GitHub.
3. Gera link como `https://tp-hub.vercel.app`.

---

### Opção C — GitHub Pages (gratuito, requer conta GitHub)

1. Crie um repositório no GitHub chamado `tp-hub`.
2. Faça upload do `dashboard_colaboradores.html` e renomeie para `index.html`.
3. Vá em **Settings → Pages → Source: main branch**.
4. O site fica em `https://SEU-USUARIO.github.io/tp-hub`.

---

### Opção D — Domínio próprio do escritório

Se o escritório já tem hospedagem web (como HostGator, Locaweb, GoDaddy):
1. Acesse o painel de hospedagem (cPanel ou similar).
2. Vá em **Gerenciador de Arquivos**.
3. Faça upload do `dashboard_colaboradores.html` na pasta `public_html` com o nome `index.html`.
4. O hub fica acessível em `https://www.tulioparca.com.br` ou um subdomínio como `https://hub.tulioparca.com.br`.

---

## PARTE 3 — Fluxo completo recomendado

```
Arquivo HTML local
       ↓
  Integrar Supabase (banco compartilhado)
       ↓
  Hospedar no Netlify (link público)
       ↓
  Configurar domínio hub.tulioparca.com.br
       ↓
  Compartilhar o link com a equipe
```

Com esse fluxo, qualquer colaborador acessa pelo celular ou computador, faz login com seu nome, marca suas tarefas e o sócio vê tudo em tempo real no painel de gestão.

---

## Resumo dos custos

| Serviço | Plano | Custo |
|---|---|---|
| Supabase | Free (500MB, 50k linhas) | **Gratuito** |
| Netlify | Starter | **Gratuito** |
| Domínio `.com.br` | Registro.br | ~R$ 40/ano |

Para um escritório de advocacia de pequeno/médio porte, o plano gratuito do Supabase é suficiente por vários anos.

---

*Gerado para Túlio Parca Advogados — Hub de Rotinas*
