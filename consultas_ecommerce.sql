-- =====================================================================
-- PROJETO FINAL EBAC: Análise de vendas de e-commerce
-- Base pública: bigquery-public-data.thelook_ecommerce (BigQuery, região US)
-- Tabelas cruzadas: order_items, products, users (+ orders)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PREPARAÇÃO: cópia das tabelas públicas para o meu projeto
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS `modulogcloud.ecommerce_analise` OPTIONS (location = 'US');

CREATE OR REPLACE TABLE `modulogcloud.ecommerce_analise.orders`      AS SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;
CREATE OR REPLACE TABLE `modulogcloud.ecommerce_analise.order_items` AS SELECT * FROM `bigquery-public-data.thelook_ecommerce.order_items`;
CREATE OR REPLACE TABLE `modulogcloud.ecommerce_analise.users`       AS SELECT * FROM `bigquery-public-data.thelook_ecommerce.users`;
CREATE OR REPLACE TABLE `modulogcloud.ecommerce_analise.products`    AS SELECT * FROM `bigquery-public-data.thelook_ecommerce.products`;

-- ---------------------------------------------------------------------
-- 2. ANÁLISES EXPLORATÓRIAS
-- ---------------------------------------------------------------------

-- 2.1 Distribuição de itens por status
SELECT status,
       COUNT(*) AS itens,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct
FROM `modulogcloud.ecommerce_analise.order_items`
GROUP BY status
ORDER BY itens DESC;

-- 2.2 Receita mensal (vendas válidas: exclui cancelados e devolvidos)
SELECT FORMAT_DATE('%Y-%m', DATE(created_at)) AS ano_mes,
       ROUND(SUM(sale_price), 2) AS receita
FROM `modulogcloud.ecommerce_analise.order_items`
WHERE status NOT IN ('Cancelled', 'Returned')
GROUP BY ano_mes
ORDER BY ano_mes;

-- 2.3 Receita anual e número de pedidos
SELECT EXTRACT(YEAR FROM created_at) AS ano,
       COUNT(DISTINCT order_id) AS pedidos,
       ROUND(SUM(sale_price), 2) AS receita,
       ROUND(AVG(sale_price), 2) AS preco_medio_item
FROM `modulogcloud.ecommerce_analise.order_items`
WHERE status NOT IN ('Cancelled', 'Returned')
GROUP BY ano
ORDER BY ano;

-- 2.4 Receita e margem por categoria
SELECT p.category AS categoria,
       ROUND(SUM(oi.sale_price), 2) AS receita,
       ROUND(AVG((oi.sale_price - p.cost) / oi.sale_price) * 100, 1) AS margem_pct
FROM `modulogcloud.ecommerce_analise.order_items` oi
JOIN `modulogcloud.ecommerce_analise.products` p ON oi.product_id = p.id
WHERE oi.status NOT IN ('Cancelled', 'Returned')
GROUP BY categoria
ORDER BY receita DESC;

-- 2.5 Estatísticas de preço e outliers (regra do IQR)
WITH q AS (
  SELECT APPROX_QUANTILES(sale_price, 4) AS quartis
  FROM `modulogcloud.ecommerce_analise.order_items`
  WHERE status NOT IN ('Cancelled', 'Returned')
)
SELECT COUNT(*) AS itens,
       ROUND(AVG(sale_price), 2) AS media,
       ROUND(APPROX_QUANTILES(sale_price, 2)[OFFSET(1)], 2) AS mediana,
       ROUND(STDDEV(sale_price), 2) AS desvio_padrao,
       MIN(sale_price) AS minimo,
       MAX(sale_price) AS maximo,
       COUNTIF(sale_price > (SELECT quartis[OFFSET(3)] + 1.5 * (quartis[OFFSET(3)] - quartis[OFFSET(1)]) FROM q)) AS outliers
FROM `modulogcloud.ecommerce_analise.order_items`
WHERE status NOT IN ('Cancelled', 'Returned');

-- 2.6 Receita por país e canal de aquisição
SELECT u.country AS pais,
       u.traffic_source AS canal,
       ROUND(SUM(oi.sale_price), 2) AS receita
FROM `modulogcloud.ecommerce_analise.order_items` oi
JOIN `modulogcloud.ecommerce_analise.users` u ON oi.user_id = u.id
WHERE oi.status NOT IN ('Cancelled', 'Returned')
GROUP BY pais, canal
ORDER BY receita DESC;

-- ---------------------------------------------------------------------
-- 3. DIAGNÓSTICO DE QUALIDADE (nulos, duplicidades, inconsistências)
-- ---------------------------------------------------------------------
SELECT
  COUNTIF(sale_price < 1)                           AS itens_preco_menor_que_1,
  COUNT(*) - COUNT(DISTINCT id)                     AS ids_duplicados,
  COUNTIF(delivered_at < created_at)                AS entrega_antes_do_pedido,
  COUNTIF(shipped_at IS NULL)                       AS sem_data_envio,
  COUNTIF(delivered_at IS NULL)                     AS sem_data_entrega,
  COUNTIF(returned_at IS NULL)                      AS sem_data_devolucao
FROM `modulogcloud.ecommerce_analise.order_items`;

SELECT COUNTIF(age < 0 OR age > 120) AS idades_invalidas,
       COUNTIF(country IS NULL)      AS paises_nulos,
       COUNT(DISTINCT country)       AS paises_distintos
FROM `modulogcloud.ecommerce_analise.users`;

SELECT COUNTIF(cost IS NULL OR cost <= 0) AS custos_invalidos
FROM `modulogcloud.ecommerce_analise.products`;

-- ---------------------------------------------------------------------
-- 4. TRATAMENTO: tabela final unificada (3 tabelas cruzadas)
--    - remove itens com preço < 1 (inconsistência)
--    - padroniza datas, país (Brasil -> Brazil) e gênero
--    - colunas derivadas: ano_mes, ano, margem, margem_pct, dias_ate_envio,
--      dias_ate_entrega, foi_entregue, foi_devolvido, faixa_etaria
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `modulogcloud.ecommerce_analise.vendas_analise` AS
SELECT
  oi.id                                              AS item_id,
  oi.order_id                                        AS pedido_id,
  DATE(oi.created_at)                                AS data_pedido,
  FORMAT_DATE('%Y-%m', DATE(oi.created_at))          AS ano_mes,
  EXTRACT(YEAR FROM oi.created_at)                   AS ano,
  oi.status                                          AS status,
  p.category                                         AS categoria,
  p.department                                       AS departamento,
  p.brand                                            AS marca,
  ROUND(p.cost, 2)                                   AS custo,
  ROUND(oi.sale_price, 2)                            AS preco_venda,
  ROUND(oi.sale_price - p.cost, 2)                   AS margem,
  ROUND((oi.sale_price - p.cost) / oi.sale_price * 100, 1) AS margem_pct,
  DATE_DIFF(DATE(oi.shipped_at),   DATE(oi.created_at), DAY) AS dias_ate_envio,
  DATE_DIFF(DATE(oi.delivered_at), DATE(oi.created_at), DAY) AS dias_ate_entrega,
  oi.delivered_at IS NOT NULL                        AS foi_entregue,
  oi.returned_at  IS NOT NULL                        AS foi_devolvido,
  u.id                                               AS cliente_id,
  CASE WHEN u.age < 25 THEN '18-24'
       WHEN u.age < 35 THEN '25-34'
       WHEN u.age < 45 THEN '35-44'
       WHEN u.age < 55 THEN '45-54'
       ELSE '55+' END                                AS faixa_etaria,
  CASE u.gender WHEN 'M' THEN 'Masculino'
                WHEN 'F' THEN 'Feminino'
                ELSE 'Não informado' END             AS genero,
  IF(u.country = 'Brasil', 'Brazil', u.country)      AS pais,
  u.state                                            AS estado,
  u.traffic_source                                   AS canal
FROM `modulogcloud.ecommerce_analise.order_items` oi
JOIN `modulogcloud.ecommerce_analise.products` p ON oi.product_id = p.id
JOIN `modulogcloud.ecommerce_analise.users`    u ON oi.user_id    = u.id
WHERE oi.sale_price >= 1;

-- Correção de rótulo: a faixa inicial inclui idades de 12 a 24 anos
UPDATE `modulogcloud.ecommerce_analise.vendas_analise`
SET faixa_etaria = '0-24'
WHERE faixa_etaria = '18-24';

-- ---------------------------------------------------------------------
-- 5. VALIDAÇÃO (batida com o dashboard: Brazil = 1.196.250,76)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS linhas FROM `modulogcloud.ecommerce_analise.vendas_analise`;  -- 181.087

SELECT ROUND(SUM(preco_venda), 2) AS receita_brazil
FROM `modulogcloud.ecommerce_analise.vendas_analise`
WHERE pais = 'Brazil' AND status NOT IN ('Cancelled', 'Returned');
