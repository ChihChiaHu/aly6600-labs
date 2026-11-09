-- ALY 6600 Lab 8: CTEs, BI Connection and Git
-- Student: Justin (Chih Chia) Hu

USE sakila;

-- ---------------------------------------------------------------------
-- PART 1: WRITE
-- Task 1: Single CTE
-- Customers whose total spending is above the average customer total
-- ---------------------------------------------------------------------

WITH customer_spend AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        SUM(p.amount) AS total_spend
    FROM customer c
    JOIN payment p ON c.customer_id = p.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name)
SELECT
    customer_id,
    first_name,
    last_name,
    total_spend
FROM customer_spend
WHERE total_spend > (SELECT AVG(total_spend) FROM customer_spend)
ORDER BY total_spend DESC;


-- ---------------------------------------------------------------------
-- Task 2: Chained CTEs
-- Top five stores by number of above-average-spending customers,
-- with each store's total revenue from those customers
-- ---------------------------------------------------------------------
-- Step 1: total spend per customer
WITH customer_spend AS (            
    SELECT
        p.customer_id,
        SUM(p.amount) AS total_spend
    FROM payment p
    GROUP BY p.customer_id),
-- Step 2: keep only above-average customers
above_avg_customers AS (            
    SELECT
        customer_id,
        total_spend
    FROM customer_spend
    WHERE total_spend > (SELECT AVG(total_spend) FROM customer_spend)),
-- Step 3: attach store information
customer_store AS (                 
    SELECT
        a.customer_id,
        a.total_spend,
        s.store_id,
        ci.city AS store_city
    FROM above_avg_customers a
    JOIN customer c  ON a.customer_id = c.customer_id
    JOIN store s     ON c.store_id    = s.store_id
    JOIN address ad  ON s.address_id  = ad.address_id
    JOIN city ci     ON ad.city_id    = ci.city_id
)
-- Step 4: aggregate, rank, limit
SELECT                              
    store_id,
    store_city,
    COUNT(customer_id)                            AS above_avg_customers,
    ROUND(SUM(total_spend), 2)                    AS revenue_from_above_avg,
    RANK() OVER (ORDER BY COUNT(customer_id) DESC) AS store_rank
FROM customer_store
GROUP BY store_id, store_city
ORDER BY store_rank, revenue_from_above_avg DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- Task 3: BI tool connection (done in Tableau / Power BI, screenshot submitted)
-- Query used in the BI tool: the Task 2 query above, pasted as Custom SQL
-- (Tableau) or as a native SQL statement (Power BI "Advanced options").
-- Visualization: bar chart of above_avg_customers by store_city
-- Filter: store_city (category filter / slicer)
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Task 4: Git basics (done in terminal, screenshot submitted)
--   git clone <course-repo-url>
--   cd <repo-folder>
--   (save this file as lab8_justin_hu.sql in the repo)
--   git add lab8_justin_hu.sql
--   git commit -m "Add Lab 8 CTE queries"
--   git push origin main
--   git log --oneline        -- for the commit history screenshot
-- ---------------------------------------------------------------------


-- =====================================================================
-- PART 2: EXPLAIN
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Task 1 rewritten with a subquery in the FROM clause
-- ---------------------------------------------------------------------
SELECT
    cs.customer_id,
    cs.first_name,
    cs.last_name,
    cs.total_spend
FROM (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        SUM(p.amount) AS total_spend
    FROM customer c
    JOIN payment p ON c.customer_id = p.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
) AS cs
WHERE cs.total_spend > (
    SELECT AVG(t.total_spend)
    FROM (
        SELECT SUM(amount) AS total_spend
        FROM payment
        GROUP BY customer_id
    ) AS t
)
ORDER BY cs.total_spend DESC;

/*
Q1 Answer:
Both queries return the same customers in the same order. I find the CTE
version more readable. In the CTE version, customer_spend is defined once
at the top and then reused twice: once in the outer FROM and once inside
the AVG() subquery. In the subquery version, a derived table cannot be
referenced again by name, so I had to write the per-customer SUM logic a
second time just to get the average. That duplication means if I change
how spend is calculated, I have to remember to change it in two places.
The CTE also reads top to bottom (build the totals, then filter), while
the subquery version has to be read from the inside out.

For a one-step query like Task 1 the difference is small. I think the
advantage becomes significant at around two to three steps. Task 2 has
three CTEs feeding a final SELECT, and writing that as nested subqueries
would mean three levels of nesting plus the repeated average logic, which
would be hard to read and debug. With CTEs I could also test each step on
its own by running SELECT * FROM that CTE.
*/

/*
Q2 Answer:
No. In my Task 2 query, customer_spend (the first CTE) cannot reference
customer_store (the third CTE). A CTE can only reference CTEs that were
defined before it in the same WITH clause, plus regular tables. When MySQL
reads customer_spend, customer_store does not exist yet, so it would fail
with a "table doesn't exist" error. That is why my order is customer_spend,
then above_avg_customers (reads customer_spend), then customer_store (reads
above_avg_customers). Each step only looks backward. The one exception is
WITH RECURSIVE, where a CTE can reference itself, but it still cannot
reference a CTE defined after it.
*/

/*
Q3 Answer:
It depends on how the data source was set up. With a live connection, the
BI tool does not filter the rows it already has. When I pick a store_city
in the filter, the tool rewrites the SQL, usually by wrapping my Task 2
query as a subquery and adding a WHERE store_city = '...' clause, and
sends it back to the warehouse. The warehouse runs it and returns the new
result, so the data is always current but every click costs a query.

With an extract (Tableau Hyper extract or Power BI Import mode), my query
ran once and the results were copied into the BI tool's own engine. Filter
clicks are then handled locally in that copy, so they are fast and do not
hit the warehouse, but the data is only as fresh as the last refresh. For
my Task 2 result, which is only a couple of rows, an extract makes more
sense. A live connection fits better when the data changes often or is too
large to copy.
*/

/*
Q4 Answer:
dbt models are just .sql files, and dbt is built around the idea that
analytics code should be treated like software. Git gives dbt a history of
every change to a model, branches for testing changes before they reach
production, pull requests for review, and a way for dbt Cloud or a CI job
to deploy a specific version of the project. Without Git there is no
reliable record of which version of a model built a table.

In Task 4, Git tracked exactly what I changed and when, with the commit
message "Add Lab 8 CTE queries". If two teammates edited the same .sql file
without version control, for example on a shared drive, whoever saved last
would overwrite the other person's work with no warning and no way to get
it back. With Git, the second person's push is rejected until they pull,
and if both edited the same lines Git shows a merge conflict so they can
decide together which version to keep.
*/


-- =====================================================================
-- PART 3: EXTEND
-- Most recent rental, days since, Active / At Risk / Lapsed classification,
-- top 20 At Risk customers by lifetime spend
--
-- Note on the reference date: Sakila rentals stop in February 2006, so
-- using CURDATE() would make every customer "Lapsed". I used the latest
-- rental_date in the data as the "today" date so the classification is
-- meaningful. To use the real current date, replace the ref_date CTE with
-- SELECT CURDATE() AS ref_date.
-- =====================================================================
WITH ref_date AS (
    SELECT DATE(MAX(rental_date)) AS ref_date
    FROM rental
),
customer_recency AS (               -- recency calculation
    SELECT
        r.customer_id,
        DATE(MAX(r.rental_date))                        AS last_rental_date,
        DATEDIFF(rd.ref_date, DATE(MAX(r.rental_date))) AS days_since_rental
    FROM rental r
    CROSS JOIN ref_date rd
    GROUP BY r.customer_id, rd.ref_date
),
customer_lifetime AS (              -- lifetime spend per customer
    SELECT
        customer_id,
        SUM(amount) AS lifetime_spend
    FROM payment
    GROUP BY customer_id
),
customer_status AS (                -- classification with CASE WHEN
    SELECT
        cr.customer_id,
        cr.last_rental_date,
        cr.days_since_rental,
        cl.lifetime_spend,
        CASE
            WHEN cr.days_since_rental <= 90  THEN 'Active'
            WHEN cr.days_since_rental <= 180 THEN 'At Risk'
            ELSE 'Lapsed'
        END AS customer_status
    FROM customer_recency cr
    JOIN customer_lifetime cl ON cr.customer_id = cl.customer_id
)
SELECT
    cs.customer_id,
    c.first_name,
    c.last_name,
    cs.last_rental_date,
    cs.days_since_rental,
    cs.customer_status,
    cs.lifetime_spend
FROM customer_status cs
JOIN customer c ON cs.customer_id = c.customer_id
WHERE cs.customer_status = 'At Risk'
ORDER BY cs.lifetime_spend DESC
LIMIT 20;
