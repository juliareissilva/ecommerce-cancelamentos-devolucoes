# Cancelamentos e devoluções em e-commerce: análise de dados e modelo preditivo

**Projeto de parceria EBAC × Semantix: Analista de Dados**


## 1. O problema

Em um e-commerce, itens cancelados ou devolvidos significam receita perdida, custo logístico e desgaste com o cliente. Na base analisada, **24,8% de todos os itens vendidos** terminam cancelados (14,7%) ou devolvidos (10,1%). Entre os itens com desfecho já conhecido (concluídos, cancelados ou devolvidos), a taxa de perda chega a **49,7%**.

**Pergunta do projeto:** dá para identificar, com informações conhecidas no momento da compra, quais itens têm maior risco de cancelamento ou devolução, e quais perfis concentram esse risco?

**Por que usar dados:** sem dados, o problema só é percebido depois que acontece. Com dados, é possível localizar onde o risco se concentra, priorizar ações de prevenção e testar objetivamente se um modelo consegue antecipar o desfecho.

## 2. Coleta de dados

| Item | Descrição |
|---|---|
| Fonte | Dataset público `bigquery-public-data.thelook_ecommerce` (Google BigQuery) |
| Natureza | **Sintético** (gerado para fins didáticos), estruturado e não confidencial |
| Tabelas usadas | `order_items` (itens vendidos), `products` (produtos), `users` (clientes) e `orders` (pedidos) |
| Acesso | Consulta SQL no BigQuery; cópia das tabelas para o projeto próprio (`ecommerce_analise`) |
| Volume | 181.087 itens após o tratamento, 23 colunas, de 2019 a 2026, 16 países |

Todo o código SQL está em [`sql/consultas_ecommerce.sql`](sql/consultas_ecommerce.sql).

### Tratamento dos dados

- **Cruzamento** das tabelas de itens, produtos e clientes em uma única tabela analítica (`vendas_analise`).
- **Inconsistências:** remoção de 19 itens com preço de venda menor que 1; verificação de duplicidades (nenhuma), idades, países e custos inválidos (nenhum).
- **Padronização:** país (`Brasil` → `Brazil`), gênero (`M`/`F` → Masculino/Feminino/Não informado) e datas.
- **Nulos:** as datas de envio, entrega e devolução vazias são estruturais (refletem o status do item), e não erro de dado.
- **Colunas derivadas:** `ano_mes`, `ano`, `margem`, `margem_pct`, `dias_ate_envio`, `dias_ate_entrega`, `foi_entregue`, `foi_devolvido` e `faixa_etaria`.

A tabela final está em [`dados/base_tratada.csv`](dados/).

## 3. Análise exploratória

Visão geral do negócio (itens com venda válida, isto é, sem cancelados e devolvidos):

- **Receita total de cerca de 8,12 milhões**, com crescimento contínuo de 2019 (68 mil) até 2026 (3,02 milhões).
- **Preço:** média de 59,59, mediana de 39,99 e 8,5% de itens fora do padrão (outliers) com preços altos, o que puxa a média para cima da mediana.
- **Categorias:** Outerwear & Coats e Jeans lideram a receita; as maiores margens estão em Blazers & Jackets (62,0%), Accessories (59,9%) e Suits (59,8%), e a menor em Tops & Tees (44,0%).
- **Canais e países:** o canal Search responde por cerca de 70% das vendas; China, Estados Unidos e Brasil lideram a receita.
- **Status:** Shipped 30,1%, Complete 25,1%, Processing 20,0%, Cancelled 14,7% e Returned 10,1%.

A análise de risco por segmento (taxa de perda por canal, país, categoria, faixa etária, faixa de preço e ano) e a associação de cada variável com o alvo (V de Cramér) estão no notebook [`notebooks/modelagem_cancelamentos.ipynb`](notebooks/modelagem_cancelamentos.ipynb), com os gráficos em [`figuras/`](figuras/).

O dashboard interativo, com 3 indicadores e 5 gráficos (receita no tempo, categorias, mapa por país, canais e faixa etária) e filtros por ano, país e categoria, está no Looker Studio:

**Dashboard:** https://datastudio.google.com/s/lMqn9A7qadw

## 4. Modelagem

**Alvo:** `perdido` = 1 se o item foi cancelado ou devolvido; 0 se foi concluído. Itens ainda em `Processing` ou `Shipped` ficam de fora, porque o desfecho deles ainda não é conhecido e tratá-los como "não perdidos" criaria rótulos falsos. A modelagem usa **90.292 itens**.

**Variáveis (todas conhecidas na hora da compra):** preço, custo, margem, ano, mês e dia da semana do pedido, categoria, departamento, marca (30 maiores, resto agrupado), faixa etária, gênero, país e canal.

**Vazamento de dados evitado:** ficaram de fora `foi_devolvido`, `foi_entregue`, `dias_ate_envio` e `dias_ate_entrega`, que só existem depois do desfecho e "entregariam" a resposta.

**Divisão:** 80% treino e 20% teste, estratificada pelo alvo (semente fixa, para reprodutibilidade).

**Modelos comparados:**
1. Baseline: prevê sempre a classe mais comum (piso de comparação).
2. Regressão logística: modelo estatístico interpretável.
3. Random Forest (200 árvores, profundidade máxima 12): modelo de machine learning que captura relações não lineares.

**Avaliação:** acurácia, precisão, recall, F1 e AUC-ROC no conjunto de teste, matriz de confusão, curvas ROC e importância das variáveis por permutação.

### Resultados (conjunto de teste)

| Modelo | Acurácia | Precisão | Recall | F1 | AUC-ROC |
|---|---|---|---|---|---|
| Baseline | 0,5035 | 0,000 | 0,000 | 0,000 | 0,5000 |
| Regressão logística | 0,5060 | 0,503 | 0,4175 | 0,4563 | 0,5070 |
| Random Forest | 0,5163 | 0,518 | 0,3701 | 0,4317 | **0,5166** |

## 5. Conclusões

1. **O desempenho dos modelos é próximo do acaso.** O melhor modelo (Random Forest) tem AUC de 0,517, contra 0,500 do baseline, e acurácia de 51,6%, contra 50,3%. Na prática, as informações conhecidas na hora da compra **não conseguem prever** se um item será cancelado ou devolvido.
2. **Isso é um resultado válido, não uma falha.** Seria enganoso apresentar um modelo com esse desempenho como solução. A conclusão é que, nesta base, o cancelamento e a devolução não dependem de forma relevante de categoria, preço, canal, país ou perfil do cliente. A variável apontada como mais importante (faixa etária) tem efeito desprezível, considerando a AUC tão baixa.
3. **A explicação mais provável é a natureza sintética dos dados**, em que o desfecho do pedido é gerado de forma essencialmente aleatória. Em uma operação real, esperaríamos mais sinal.
4. **O problema é grande, mesmo sem ser previsível:** um quarto dos itens vendidos é perdido, e metade dos itens com desfecho conhecido. Acompanhar essa taxa continuamente é, por si só, valioso.

### Recomendações

- **Não colocar este modelo em produção**, pois não reduziria perdas de forma confiável.
- **Enriquecer os dados** com variáveis que provavelmente explicam o comportamento real: forma de pagamento, valor do frete e prazo prometido, desconto aplicado, histórico de compras e devoluções do cliente, disponibilidade de estoque e dispositivo de compra.
- **Modelar em outro momento do funil:** sinais pós-compra (atraso no envio, tempo em processamento) podem prever melhor o cancelamento e merecem um modelo próprio.
- **Monitorar a taxa de perda como indicador-chave**, por categoria e canal, no dashboard.

### Limitações

- Dados sintéticos: os padrões não representam uma loja real.
- Não foram feitos ajuste fino de hiperparâmetros nem testes de outros algoritmos, porque o sinal quase inexistente tornaria o ganho irrelevante.
- A divisão treino/teste foi aleatória, e não temporal.

## 6. Estrutura do repositório

```
.
├── README.md                          # esta documentação
├── notebooks/
│   └── modelagem_cancelamentos.ipynb  # análise exploratória e modelagem
├── sql/
│   └── consultas_ecommerce.sql        # coleta, diagnóstico e tratamento
├── dados/
│   └── base_tratada.csv               # tabela final tratada
├── figuras/                           # gráficos gerados no notebook
├── resultados_modelos.csv             # métricas dos modelos
└── relatorio_insights.pdf             # relatório de insights
```

## 7. Como reproduzir

1. Execute as consultas de `sql/consultas_ecommerce.sql` no BigQuery (ou use direto o arquivo `dados/base_tratada.csv`).
2. Abra `notebooks/modelagem_cancelamentos.ipynb` no Google Colab.
3. Para ler do CSV, troque `FONTE = "bigquery"` por `FONTE = "csv"` na primeira célula e envie o `base_tratada.csv` ao Colab.
4. Execute as células em ordem.

**Ferramentas:** Google BigQuery (SQL), Python (pandas, scikit-learn, matplotlib, scipy), Google Colab e Looker Studio.
