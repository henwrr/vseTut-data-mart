/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/
/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Раковский Александр
 * Дата: 06.10.25
*/


/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
 */
WITH order_payments_agg AS (
    SELECT
        order_id,
        MAX(CASE WHEN payment_installments > 1 THEN 1 ELSE 0 END) AS has_installments,
        MAX(CASE WHEN LOWER(payment_type) LIKE '%промокод%' OR payment_type = 'промокод' THEN 1 ELSE 0 END) AS has_promo,
        MAX(CASE WHEN payment_sequential = 1 AND payment_type = 'денежный перевод' THEN 1 ELSE 0 END) AS first_payment_is_transfer
    FROM ds_ecom.order_payments
    GROUP BY order_id
),
order_costs AS (
    SELECT
        o.order_id,
        SUM(price + delivery_cost) AS order_total_cost
    FROM ds_ecom.orders o
    JOIN ds_ecom.order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'Доставлено'
    GROUP BY o.order_id
),
order_ratings_agg AS (
    SELECT
        order_id,
        AVG(
            CASE 
                WHEN review_score >= 10 THEN review_score / 10.0
                ELSE review_score 
            END
        ) AS avg_review_score_per_order
    FROM ds_ecom.order_reviews
    WHERE review_score IS NOT NULL
    GROUP BY order_id
),
top_regions AS (
    SELECT u.region
    FROM ds_ecom.orders o
    JOIN ds_ecom.users u ON o.buyer_id = u.buyer_id
    WHERE o.order_status IN ('Доставлено', 'Отменено')
    GROUP BY u.region
    ORDER BY COUNT(*) DESC
    LIMIT 3
),
filtered_orders AS (
    SELECT
        o.order_id,
        o.buyer_id,
        o.order_status,
        o.order_purchase_ts,
        u.user_id,
        u.region
    FROM ds_ecom.orders o
    JOIN ds_ecom.users u ON o.buyer_id = u.buyer_id
    WHERE o.order_status IN ('Доставлено', 'Отменено')
    AND u.region IN (SELECT region FROM top_regions)
),
user_stats AS (
    SELECT
        fo.user_id,
        fo.region,
        MIN(fo.order_purchase_ts) AS first_order_ts,
        MAX(fo.order_purchase_ts) AS last_order_ts,
        (MAX(fo.order_purchase_ts) - MIN(fo.order_purchase_ts))::TEXT AS lifetime,
        COUNT(DISTINCT fo.order_id) AS total_orders,
        COALESCE(AVG(ora.avg_review_score_per_order), 0) AS avg_order_rating,
        COUNT(DISTINCT CASE WHEN ora.order_id IS NOT NULL THEN fo.order_id END) AS num_orders_with_rating,
        COUNT(DISTINCT CASE WHEN fo.order_status = 'Отменено' THEN fo.order_id END) AS num_canceled_orders,
        CASE 
            WHEN COUNT(DISTINCT fo.order_id) > 0 
            THEN ROUND(COUNT(DISTINCT CASE WHEN fo.order_status = 'Отменено' THEN fo.order_id END)::numeric * 100.0 / COUNT(DISTINCT fo.order_id)::numeric, 4)
            ELSE 0 
        END AS canceled_orders_ratio,
        ROUND(SUM(COALESCE(oc.order_total_cost, 0))::numeric, 2) AS total_order_costs,
        ROUND(AVG(oc.order_total_cost)::numeric, 2) AS avg_order_cost,
        COUNT(DISTINCT CASE WHEN opa.has_installments = 1 THEN fo.order_id END) AS num_installment_orders,
        COUNT(DISTINCT CASE WHEN opa.has_promo = 1 THEN fo.order_id END) AS num_orders_with_promo,
        MAX(CASE WHEN opa.first_payment_is_transfer = 1 THEN 1 ELSE 0 END) AS used_money_transfer,
        MAX(COALESCE(opa.has_installments, 0)) AS used_installments,
        MAX(CASE WHEN fo.order_status = 'Отменено' THEN 1 ELSE 0 END) AS used_cancel
    FROM filtered_orders fo
    LEFT JOIN order_costs oc ON fo.order_id = oc.order_id
    LEFT JOIN order_payments_agg opa ON fo.order_id = opa.order_id
    LEFT JOIN order_ratings_agg ora ON fo.order_id = ora.order_id
    GROUP BY fo.user_id, fo.region
)
SELECT *
FROM user_stats
WHERE total_orders >= 3
ORDER BY total_orders DESC, num_installment_orders DESC, region, user_id;


/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Напишите ваш запрос тут
WITH user_segments AS (
    SELECT 
        user_id,
        total_orders,
        avg_order_cost,
        CASE
            WHEN total_orders = 1 THEN '1 заказ'
            WHEN total_orders BETWEEN 2 AND 5 THEN '2 — 5 заказов'
            WHEN total_orders BETWEEN 6 AND 10 THEN '6 — 10 заказов'
            ELSE '11 и более заказов'
        END AS order_segment
    FROM ds_ecom.product_user_features
)
SELECT 
    order_segment,
    COUNT(DISTINCT user_id) AS total_users,
    ROUND(AVG(total_orders)::numeric, 2) AS avg_orders_per_user,
    ROUND(AVG(avg_order_cost)::numeric, 2) AS avg_order_cost
FROM user_segments
GROUP BY order_segment
ORDER BY 
    CASE order_segment
        WHEN '1 заказ' THEN 1
        WHEN '2 — 5 заказов' THEN 2
        WHEN '6 — 10 заказов' THEN 3
        ELSE 4
    END;
/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * Всего 62400 пользоватлей, 60460 пользователей совершили 1 заказ, 2-5 заказов совершили 1934 пользователя,
 * 6-10 заказов свовершили 5 пользователей, а 11 и более заказов совершили только один пользователь. (avg_order_cost)-средний чек по сегментам:
 * 1 заказ: 3,324.08 рублей, 2-5 заказов: 3,091.36 рублей, 6-10 заказов: 2,772.90 рублей, 11+ заказов: 1,244.80 рублей. (avg_orders_per_user) Среднее кол-во заказов на 
 * пользователя по сегментам: 1 заказ: 1, 2-5 заказов: 2.09, 6-10 заказов: 7, 11+ заказов: 15.
 * */



/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Напишите ваш запрос тут
 /* Задача 2. Ранжирование пользователей */
SELECT 
    user_id,
    region,
    total_orders,
    ROUND(avg_order_cost, 2) AS avg_order_cost,
    RANK() OVER (ORDER BY avg_order_cost DESC) AS rank
FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15;
 /* Напишите краткий комментарий с выводами по результатам задачи 2.
 * Топ 15 пользователей с 3 более заказами имеют средний чек от минимального 5526.67 до максимального 14716.67, эти пользователи из 3 регионов:Санкт-Петербург,
 * Москва, Новосибирская область. Распределение пользователей по регионам: Москва: 9 пользователей, Санкт-Петербург: 4 пользователя, 
 * Новосибирская область: 2 пользователя. Кол-во заказов у пользователей: 3 заказа: 13 пользователей, 4 заказа: 1 пользователь,  5 заказов: 1 пользователь
*/



/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Напишите ваш запрос тут
SELECT 
    region,
    COUNT(DISTINCT user_id) AS total_clients,
    SUM(total_orders) AS total_orders,
    ROUND(AVG(avg_order_cost), 2) AS avg_order_cost_region,
    ROUND(SUM(num_installment_orders) * 100.0 / NULLIF(SUM(total_orders), 0), 2) AS installment_ratio_percent,
    ROUND(SUM(num_orders_with_promo) * 100.0 / NULLIF(SUM(total_orders), 0), 2) AS promo_ratio_percent,
    ROUND(COUNT(DISTINCT CASE WHEN used_cancel = 1 THEN user_id END) * 100.0 / NULLIF(COUNT(DISTINCT user_id), 0), 2) AS users_with_cancel_ratio_percent
FROM ds_ecom.product_user_features
GROUP BY region
ORDER BY total_orders DESC;

/* Напишите краткий комментарий с выводами по результатам задачи 3.
 * avg_order_cost_region - Средняя стоимость одного заказа в регионе, 
 * installment_orders_ratio - Доля заказов в рассрочку,
 * promo_orders_ratio - Доля заказов с промокодами,
 * users_with_cancel_ratio - Доля пользователей с отменами
 * 1. Москва лидирует по клиентам (39 386) и заказам (40 747), но имеет самый низкий средний чек (3 167) и наименьшую долю рассрочки (47.73%).
2. Санкт-Петербург показывает лучшие качественные показатели: самый высокий средний чек (3 620), наибольшая доля рассрочки (54.66%) и промокодов (4.16%).
3. Новосибирская область имеет схожие с Санкт-Петербургом значения по рассрочке (54.14%) и среднему чеку (3 519), но самую низкую долю промокодов (3.68%) и отмен (0.43%)
*/


/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

-- Напишите ваш запрос тут
SELECT 
    EXTRACT(MONTH FROM first_order_ts) as first_order_month_2023,
    COUNT(DISTINCT user_id) as clients_count,
    SUM(total_orders) as total_orders,
    ROUND(AVG(avg_order_cost)::numeric, 2) as avg_order_cost,
    ROUND(AVG(avg_order_rating)::numeric, 2) as avg_rating,
    ROUND(
        COUNT(DISTINCT CASE WHEN used_money_transfer = 1 THEN user_id END) * 100.0 / 
        NULLIF(COUNT(DISTINCT user_id), 0), 
        2
    ) as money_transfer_users_percent,
    ROUND(AVG(
        EXTRACT(EPOCH FROM lifetime::interval) / 86400.0
    )::numeric, 2) as avg_lifetime_days
FROM ds_ecom.product_user_features
WHERE EXTRACT(YEAR FROM first_order_ts) = 2023
GROUP BY EXTRACT(MONTH FROM first_order_ts)
ORDER BY first_order_month_2023;

/* Напишите краткий комментарий с выводами по результатам задачи 4.
/* Задача 4. Выводы по активности пользователей по первому месяцу заказа в 2023 году:

1. Привлечение новых пользователей:
 Наименьший приток: январь (465 пользователей).Наибольший приток: ноябрь (4 703 пользователя) — пик сезонности.Второй пик: декабрь (3 589 пользователей)

2. Средний чек:
   Самый высокий: сентябрь (3 312). Самый низкий: февраль (2 581). Осенние месяцы (сентябрь-октябрь): стабильно высокие чеки (3 250-3 312)

3. Рейтинг заказов:
   Стабильно высокий (4.0-4.3 из 5).Наивысший: август (4.32). Самый низкий: ноябрь (4.00) — коррелирует с массовым притоком

4. Денежные переводы:
   Доля пользователей: 19-22%. Наибольшая: февраль (22.11%). Наименьшая: апрель (19.37%)

5. Продолжительность активности:
   Январские пользователи: 12.8 днейНоябрьские-декабрьские: 2-2.4 дня

Общий вывод:
Ноябрь — месяц массового притока (сезонность)
Осенние пользователи (сен-окт) — самые платежеспособные
Пользователи начала года — наиболее лояльные.Качество сервиса стабильно высокое

Рекомендации:
1. Изучить причины высокого среднего чека осенних пользователей
2. Поддерживать уровень сервиса для сохранения рейтинга 4+
3. Осенью фокусироваться на увеличении среднего чека
*/
 */



