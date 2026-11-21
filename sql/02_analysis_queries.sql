-- ============================================================================
-- Music Store Database - Analysis Queries
-- ============================================================================
-- Target DBMS : PostgreSQL 12+
-- Prerequisite: run 01_create_tables.sql and load the CSVs (see README.md).
--
-- The questions are grouped by difficulty: Easy, Moderate, Advanced.
--
-- Fixes applied versus data/raw/Music_Store_Query.sql
--   * invoice_line (the original used the non-existent name "invoiceline")
--   * milliseconds  (the original misspelled it "miliseconds")
--   * Easy Q3 now actually returns the top 3 rows (LIMIT 3 was missing)
--   * Advanced Q2/Q3 use RANK() instead of ROW_NUMBER() so that ties are
--     returned, as the questions require
--   * every selected non-aggregated column is listed in GROUP BY
-- ============================================================================


-- ============================================================================
-- SECTION 1 - EASY
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1. Who is the most senior employee based on job title?
--     Seniority is stored as a band in employee.levels (L1 < L7).
-- ----------------------------------------------------------------------------
SELECT title,
       first_name,
       last_name,
       levels
FROM employee
ORDER BY levels DESC
LIMIT 1;


-- ----------------------------------------------------------------------------
-- Q2. Which countries have the most invoices?
-- ----------------------------------------------------------------------------
SELECT billing_country,
       COUNT(*) AS invoice_count
FROM invoice
GROUP BY billing_country
ORDER BY invoice_count DESC;


-- ----------------------------------------------------------------------------
-- Q3. What are the top 3 invoice totals?
-- ----------------------------------------------------------------------------
SELECT invoice_id,
       total
FROM invoice
ORDER BY total DESC
LIMIT 3;


-- ----------------------------------------------------------------------------
-- Q4. Which city has the best customers?
--     Returns the city with the highest sum of invoice totals, to host the
--     promotional music festival.
-- ----------------------------------------------------------------------------
SELECT billing_city,
       SUM(total) AS invoice_total
FROM invoice
GROUP BY billing_city
ORDER BY invoice_total DESC
LIMIT 1;


-- ----------------------------------------------------------------------------
-- Q5. Who is the best customer (the customer who spent the most money)?
-- ----------------------------------------------------------------------------
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       SUM(i.total) AS total_spending
FROM customer AS c
JOIN invoice AS i
  ON i.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spending DESC
LIMIT 1;


-- ============================================================================
-- SECTION 2 - MODERATE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1. Return the email, first name, last name, and genre of every Rock music
--     listener, ordered alphabetically by email.
-- ----------------------------------------------------------------------------

-- Method 1: joins + DISTINCT
SELECT DISTINCT
       c.email,
       c.first_name,
       c.last_name,
       g.name AS genre
FROM customer AS c
JOIN invoice AS i
  ON i.customer_id = c.customer_id
JOIN invoice_line AS il
  ON il.invoice_id = i.invoice_id
JOIN track AS t
  ON t.track_id = il.track_id
JOIN genre AS g
  ON g.genre_id = t.genre_id
WHERE g.name = 'Rock'
ORDER BY c.email;

-- Method 2: EXISTS avoids duplicate rows before DISTINCT is applied and is
--           usually faster on large tables.
SELECT c.email,
       c.first_name,
       c.last_name,
       'Rock' AS genre
FROM customer AS c
WHERE EXISTS (
    SELECT 1
    FROM invoice AS i
    JOIN invoice_line AS il ON il.invoice_id = i.invoice_id
    JOIN track AS t       ON t.track_id = il.track_id
    JOIN genre AS g       ON g.genre_id = t.genre_id
    WHERE i.customer_id = c.customer_id
      AND g.name = 'Rock'
)
ORDER BY c.email;


-- ----------------------------------------------------------------------------
-- Q2. Which artists have written the most Rock music?
--     Returns the top 10 rock artists and their track counts.
-- ----------------------------------------------------------------------------
SELECT ar.artist_id,
       ar.name AS artist_name,
       COUNT(*) AS rock_track_count
FROM track AS t
JOIN album AS al
  ON al.album_id = t.album_id
JOIN artist AS ar
  ON ar.artist_id = al.artist_id
JOIN genre AS g
  ON g.genre_id = t.genre_id
WHERE g.name = 'Rock'
GROUP BY ar.artist_id, ar.name
ORDER BY rock_track_count DESC, ar.name
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Q3. Which tracks are longer than the average track length?
--     Returns the track name and duration, longest first.
-- ----------------------------------------------------------------------------
SELECT name,
       milliseconds
FROM track
WHERE milliseconds > (SELECT AVG(milliseconds) FROM track)
ORDER BY milliseconds DESC;


-- ============================================================================
-- SECTION 3 - ADVANCED
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1. How much did each customer spend on the best-selling artist?
--     "Best-selling" is measured by revenue across all invoice lines.
-- ----------------------------------------------------------------------------
WITH best_selling_artist AS (
    SELECT ar.artist_id,
           ar.name AS artist_name,
           SUM(il.unit_price * il.quantity) AS total_sales
    FROM invoice_line AS il
    JOIN track AS t
      ON t.track_id = il.track_id
    JOIN album AS al
      ON al.album_id = t.album_id
    JOIN artist AS ar
      ON ar.artist_id = al.artist_id
    GROUP BY ar.artist_id, ar.name
    ORDER BY total_sales DESC
    LIMIT 1
)
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       bsa.artist_name,
       SUM(il.unit_price * il.quantity) AS amount_spent
FROM invoice AS i
JOIN customer AS c
  ON c.customer_id = i.customer_id
JOIN invoice_line AS il
  ON il.invoice_id = i.invoice_id
JOIN track AS t
  ON t.track_id = il.track_id
JOIN album AS al
  ON al.album_id = t.album_id
JOIN best_selling_artist AS bsa
  ON bsa.artist_id = al.artist_id
GROUP BY c.customer_id, c.first_name, c.last_name, bsa.artist_name
ORDER BY amount_spent DESC;


-- ----------------------------------------------------------------------------
-- Q2. What is the most popular music genre in each country?
--     Popularity is measured by the number of tracks purchased. When several
--     genres tie for first place, all of them are returned.
-- ----------------------------------------------------------------------------

-- Method 1: RANK() window function
WITH genre_purchases AS (
    SELECT c.country,
           g.genre_id,
           g.name AS genre_name,
           SUM(il.quantity) AS purchases
    FROM invoice_line AS il
    JOIN invoice AS i
      ON i.invoice_id = il.invoice_id
    JOIN customer AS c
      ON c.customer_id = i.customer_id
    JOIN track AS t
      ON t.track_id = il.track_id
    JOIN genre AS g
      ON g.genre_id = t.genre_id
    GROUP BY c.country, g.genre_id, g.name
),
ranked_genres AS (
    SELECT country,
           genre_name,
           purchases,
           RANK() OVER (PARTITION BY country ORDER BY purchases DESC) AS rnk
    FROM genre_purchases
)
SELECT country,
       genre_name,
       purchases
FROM ranked_genres
WHERE rnk = 1
ORDER BY country;

-- Method 2: join each country's purchases to that country's maximum
WITH genre_purchases AS (
    SELECT c.country,
           g.name AS genre_name,
           SUM(il.quantity) AS purchases
    FROM invoice_line AS il
    JOIN invoice AS i
      ON i.invoice_id = il.invoice_id
    JOIN customer AS c
      ON c.customer_id = i.customer_id
    JOIN track AS t
      ON t.track_id = il.track_id
    JOIN genre AS g
      ON g.genre_id = t.genre_id
    GROUP BY c.country, g.name
),
country_max AS (
    SELECT country,
           MAX(purchases) AS max_purchases
    FROM genre_purchases
    GROUP BY country
)
SELECT gp.country,
       gp.genre_name,
       gp.purchases
FROM genre_purchases AS gp
JOIN country_max AS cm
  ON cm.country = gp.country
 AND gp.purchases = cm.max_purchases
ORDER BY gp.country, gp.genre_name;


-- ----------------------------------------------------------------------------
-- Q3. Which customer spent the most on music in each country?
--     Returns every customer who shares the top amount in their country.
--
--     Country is taken from invoice.billing_country (the country the purchase
--     was billed to), matching the original analysis.
-- ----------------------------------------------------------------------------

-- Method 1: RANK() window function
WITH customer_spending AS (
    SELECT c.customer_id,
           c.first_name,
           c.last_name,
           i.billing_country AS country,
           SUM(i.total) AS total_spending
    FROM invoice AS i
    JOIN customer AS c
      ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name, i.billing_country
),
ranked_customers AS (
    SELECT country,
           first_name,
           last_name,
           customer_id,
           total_spending,
           RANK() OVER (PARTITION BY country ORDER BY total_spending DESC) AS rnk
    FROM customer_spending
)
SELECT country,
       first_name,
       last_name,
       customer_id,
       total_spending
FROM ranked_customers
WHERE rnk = 1
ORDER BY country;

-- Method 2: join each customer's spending to that country's maximum
WITH customer_spending AS (
    SELECT c.customer_id,
           c.first_name,
           c.last_name,
           i.billing_country AS country,
           SUM(i.total) AS total_spending
    FROM invoice AS i
    JOIN customer AS c
      ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name, i.billing_country
),
country_max AS (
    SELECT country,
           MAX(total_spending) AS max_spending
    FROM customer_spending
    GROUP BY country
)
SELECT cs.country,
       cs.first_name,
       cs.last_name,
       cs.customer_id,
       cs.total_spending
FROM customer_spending AS cs
JOIN country_max AS cm
  ON cm.country = cs.country
 AND cs.total_spending = cm.max_spending
ORDER BY cs.country, cs.total_spending DESC, cs.last_name;
