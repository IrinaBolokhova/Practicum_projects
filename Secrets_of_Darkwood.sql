/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Болохова Ирина
 * Дата: 19.03.2025
 * 
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT 
	COUNT(id) AS total_players, --считаю общее количество игроков
	SUM(payer) AS total_payer, --считаю количество платящих игроков
	ROUND(AVG(payer), 4) AS per_paying_players --считаю долю платящих игроков
FROM fantasy.users;
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT race,
	   COUNT(id) AS total_players, --считаю общее количество игроков для каждой расы
	   SUM(payer) AS total_payer, --считаю количество платящих игроков для каждой расы
	   ROUND(AVG(payer), 4) AS per_paying_players --считаю долю платящих игроков для каждой расы
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r ON u.race_id=r.race_id --присоединяю таблицу с расами персонажей
GROUP BY race
ORDER BY total_payer; 
-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT 
	COUNT(amount) AS total_events, --считаю общее кол-во покупок
	SUM(amount) AS total_amount, --считаю сумму всех покупок
	MIN(amount) AS min_amount, --считаю минимальную сумму покупки
	MAX(amount) AS max_amount, --считаю максимальную сумму покупки
	AVG(amount)::numeric(10,2) AS avg_amount, -- считаю среднее арифметическое стоимости покупки
	(PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount))::numeric(10,2) AS mediana_amount, --считаю медиану стоимости покупки
	STDDEV(amount)::numeric(10,2) AS std_dev_amount, --считаю стандартное отклонение стоимоти покупки
	--дополнительно считаю параметры без нулевых покупок
	(SELECT COUNT(amount) FROM fantasy.events WHERE amount<>0) AS total_without_null,
	(SELECT MIN(amount) FROM fantasy.events WHERE amount<>0) AS min_without_null,
	(SELECT AVG(amount)::numeric(10,2) FROM fantasy.events WHERE amount<>0) AS avg_without_null,
	(SELECT (PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount))::numeric(10,2) FROM fantasy.events WHERE amount<>0) AS mediana_without_null,
	(SELECT STDDEV(amount)::numeric(10,2) FROM fantasy.events WHERE amount<>0) AS std_dev_without_null
FROM fantasy.events;
-- 2.2: Аномальные нулевые покупки:
WITH count_null_events AS (--В подзадаче нахожу число нулевых покупок и общее число покупок
	SELECT 
		COUNT(transaction_id) AS total_null_events,
		(SELECT COUNT(transaction_id)
		 FROM fantasy.events
		) AS total_events
		--AVG(transaction_id) AS per_null_events
	FROM fantasy.events
	WHERE amount = 0
)
SELECT --В основном запросе вывожу число нулевых покупок, общее число покупок и нахожу долю нулевых покупок
	total_null_events,
	total_events,
	total_null_events/total_events::real AS per_null_events
FROM count_null_events;
-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
SELECT	--Считаю активность платящих игроков
	'paying_players' AS status_payer,
	COUNT(DISTINCT u.id) AS total_players, --количество игроков
	(COUNT(amount)/COUNT(DISTINCT e.id)::REAL)::numeric(10,2) AS avg_events, --среднее количество покупок
	SUM(amount)/COUNT(DISTINCT e.id)::real AS avg_amount --средняя сумма покупок
FROM fantasy.users AS u
LEFT JOIN fantasy.events AS e ON u.id=e.id
WHERE payer = 1 AND amount<>0
UNION	--Соединяю данные в одну таблицу
SELECT	--Считаю активность неплатящих игроков
	'non-paying_players' AS status_payer,
	COUNT(DISTINCT u.id) AS total_players,
	(COUNT(amount)/COUNT(DISTINCT e.id)::REAL)::numeric(10,2) AS avg_events,
	SUM(amount)/COUNT(DISTINCT e.id)::real AS avg_amount
FROM fantasy.users AS u
LEFT JOIN fantasy.events AS e ON u.id=e.id
WHERE payer = 0 AND amount<>0;
-- 2.4: Популярные эпические предметы:
WITH count_items_for_players AS ( --В подзадаче считаю долю покупающих игроков для каждого предмета
	SELECT 
		i.game_items,
		COUNT(DISTINCT u.id)/(SELECT COUNT(u.id) FROM fantasy.users AS u)::REAL per_buying_players
	FROM fantasy.events AS e 
	LEFT JOIN fantasy.items AS i ON e.item_code=i.item_code
	LEFT JOIN fantasy.users AS u ON e.id=u.id
	WHERE amount <> 0 --условием отсекаю нулевые покупки
	GROUP BY i.game_items
)
--В осном запросе вывожу количество покупок для каждого предмета, долю покупок предмета относительно всех покупок
--и долю покупающих игроков для каждого предмета из подзадачи
SELECT  
	i.game_items,
	COUNT(transaction_id) AS count_purchases,
	(COUNT(transaction_id)/(SELECT COUNT(transaction_id) FROM fantasy.events WHERE amount<>0)::REAL)::numeric(10,6) AS per_purchases,
	per_buying_players::numeric(10,5)
FROM fantasy.events AS e
LEFT JOIN fantasy.items AS i ON e.item_code=i.item_code
LEFT JOIN fantasy.users AS u ON e.id=u.id
LEFT JOIN count_items_for_players AS c ON i.game_items=c.game_items 
WHERE amount <> 0 --отсекаю нулевые покупки
GROUP BY i.game_items, per_buying_players 
ORDER BY count_purchases DESC;
-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
--Считаю кол-во игроков, кол-во совершивших покупки, кол-во платящих игроков
WITH count_players AS (
	SELECT 
		race,
		--COUNT(DISTINCT u.id) AS total_players,
		COUNT(DISTINCT e.id) AS total_buyers,
		COUNT(DISTINCT CASE WHEN payer=1 THEN e.id END) AS total_payers
	FROM fantasy.users AS u
	LEFT JOIN fantasy.race AS r ON u.race_id=r.race_id
	LEFT JOIN fantasy.events AS e ON u.id=e.id
	WHERE amount<>0
	GROUP BY race
),
--считаю общее кол-во игроков в разрезе рас
count_total_players AS (
	SELECT
		race,
		COUNT(DISTINCT u.id) AS total_players
	FROM fantasy.users AS u
	LEFT JOIN fantasy.race AS r ON u.race_id=r.race_id
	GROUP BY race
),
--Считаю доли
count_per AS (
	SELECT 
		pl.race,
		total_players,
		total_buyers,
		total_payers,
		total_buyers/total_players::real AS per_buyers,
		total_payers/total_buyers::real AS per_payers
	FROM count_players AS pl
	LEFT JOIN count_total_players AS ctp ON pl.race=ctp.race
),
--Количество покупок на игрока, сумма покупок на игрока, средняя стоимость на игрока по расам
count_purchases AS (
	SELECT 
		race,
		e.id,
		COUNT(transaction_id) AS total_purchases,
		SUM(amount) AS sum_amount,
		AVG(amount) AS avg_amount
	FROM fantasy.race AS r
	LEFT JOIN fantasy.users AS u ON r.race_id=u.race_id
	LEFT JOIN fantasy.events AS e ON u.id=e.id
	WHERE amount <> 0
	GROUP BY race, e.id
	ORDER BY race
)
--В основном запросе вывожу необходимы данные, считаю среднее кол-во покупок на игрока,
--среднюю стоимоть покупки на игрока, среднюю суммарную стоимость на игрока
SELECT 
	cp.race,
	total_players,
	total_buyers,
	total_payers,
	per_buyers::NUMERIC(10,2),
	per_payers::NUMERIC(10,2),
	(AVG(total_purchases))::NUMERIC(10,2) AS avg_purchases,
	(AVG(sum_amount)/AVG(total_purchases)::REAL)::NUMERIC(10,2) AS avg_amount,
	(AVG(sum_amount))::NUMERIC(10,2) AS avg_sum_amount
FROM count_per AS cp
LEFT JOIN count_purchases AS pu ON cp.race=pu.race 
GROUP BY cp.race, total_players,	total_buyers, total_payers,	per_buyers,	per_payers
ORDER BY total_buyers;
-- Задача 2: Частота покупок
--Считаю интервал между покупками для каждой покупки
WITH int_purchases AS (
	SELECT 
		transaction_id,
		date,
		LAG(date::DATE) OVER(PARTITION BY id ORDER BY date),
		date::DATE - LAG(date::DATE) OVER (PARTITION BY id ORDER BY date) AS int_date
	FROM fantasy.events
),
--Считаю кол-во покупок и среднее время между покупками
avg_time AS (
	SELECT
		e.id,
		COUNT(DISTINCT e.id) AS total_buyers,
		payer,
		COUNT(e.transaction_id) AS total_purchases,
		AVG(int_date) AS avg_int_date
	FROM fantasy.events AS e
	LEFT JOIN int_purchases AS ip ON e.transaction_id=ip.transaction_id
	LEFT JOIN fantasy.users AS u ON e.id=u.id
	WHERE amount<>0
	GROUP BY e.id, payer
),
--Ранжирую покупки
rank_category AS (
	SELECT 
		*,
		NTILE(3) OVER(ORDER BY avg_int_date) AS rank_id
	FROM avg_time 
	GROUP BY id, total_buyers, payer, total_purchases, avg_int_date
	HAVING total_purchases>=25 --отсекаю количество покупок
	ORDER BY rank_id
),
--устанавливаю категории частоты покупок
freq_category AS (
	SELECT
		*,
		CASE 
			WHEN rank_id=1 THEN 'высокая частота'
			WHEN rank_id=2 THEN 'умеренная частота'
			WHEN rank_id=3 THEN 'низкая частота'
		END AS frequency
	FROM rank_category 
	ORDER BY rank_id
)		
-- считаю основные показатели
	SELECT
		frequency, --категория частоты покупок
		SUM(total_buyers) AS total_buyers, --количество игроков, совершивших покупки
		SUM(payer) AS total_payers, --количество платящих игроков, среди совершивших покупки
		(SUM(payer)/SUM(total_buyers)::REAL)::numeric(10,2) AS per_payers, --доля платящих игроков
		(AVG(total_purchases))::numeric(10,2) AS avg_purchases, --среднее количество покупок на игрока
		(AVG(avg_int_date))::numeric(10,2) AS avg_interval -- среднее количество дней между покупками
	FROM freq_category
	GROUP BY frequency, rank_id
	ORDER BY avg_interval;