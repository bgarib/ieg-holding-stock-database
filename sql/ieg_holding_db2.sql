-- =====================================================================
-- IEG Holding: intraday stock database (IBM DB2)
-- Group project, SQL Based Data Architectures I, IE School of Science & Technology
-- Final consolidated answers. Load data/IEG01-03.csv into STOCK after Q1
-- (DBeaver: right click STOCK > Import Data > CSV).
-- =====================================================================

-- Q1. Raw 15-minute snapshots. Prices and volume nullable, as the files have gaps.
CREATE TABLE STOCK (
    COMPANY     CHAR(5)       NOT NULL,
    SNAPDATE    DATE          NOT NULL,
    SNAPTIME    TIME          NOT NULL,
    OPENPRICE   DECIMAL(8,4),
    HIGHPRICE   DECIMAL(8,4),
    LOWPRICE    DECIMAL(8,4),
    CLOSEPRICE  DECIMAL(8,4),
    VOLUME      INTEGER,
    CONSTRAINT PK_STOCK PRIMARY KEY (COMPANY, SNAPDATE, SNAPTIME)
);

-- Q2. Load check, then range, row count and volume per company.
SELECT COMPANY,
       AVG(OPENPRICE) + AVG(HIGHPRICE) + AVG(LOWPRICE) + AVG(CLOSEPRICE) AS CHECK1,
       AVG(VOLUME) AS CHECK2,
       COUNT(COMPANY) AS COUNT
  FROM STOCK
 GROUP BY COMPANY;

SELECT COMPANY,
       MAX(HIGHPRICE) AS MAX_PRICE,   -- highest price ever reached
       MIN(LOWPRICE)  AS MIN_PRICE,   -- lowest price ever reached
       COUNT(*)       AS NUM_ROWS,
       SUM(VOLUME)    AS TOTAL_VOLUME
  FROM STOCK
 GROUP BY COMPANY
 ORDER BY COMPANY;

-- Q3. Data-quality report: 15-minute periods on 11 Aug missing at least one company.
SELECT SNAPDATE,
       SNAPTIME,
       MAX(CASE WHEN COMPANY = 'IEG01' THEN 'OK' END) AS IEG01,
       MAX(CASE WHEN COMPANY = 'IEG02' THEN 'OK' END) AS IEG02,
       MAX(CASE WHEN COMPANY = 'IEG03' THEN 'OK' END) AS IEG03
  FROM STOCK
 WHERE SNAPDATE = '2022-08-11'
 GROUP BY SNAPDATE, SNAPTIME
HAVING COUNT(DISTINCT COMPANY) < 3
 ORDER BY SNAPTIME ASC;

-- Q4. Periods that closed down, up or flat. Rows with a NULL open or close
-- price evaluate to UNKNOWN and fall in no column, so the three do not sum to the row count.
SELECT COMPANY,
       SUM(CASE WHEN OPENPRICE > CLOSEPRICE THEN 1 ELSE 0 END) AS DECREASE,
       SUM(CASE WHEN OPENPRICE < CLOSEPRICE THEN 1 ELSE 0 END) AS INCREASE,
       SUM(CASE WHEN OPENPRICE = CLOSEPRICE THEN 1 ELSE 0 END) AS NOCHANGE
  FROM STOCK
 GROUP BY COMPANY
 ORDER BY COMPANY;

-- Q5. Daily summary: one row per company and day.
CREATE TABLE DAILY (
    COMPANY    CHAR(5)       NOT NULL,
    SNAPDATE   DATE          NOT NULL,
    HIGHPRICE  DECIMAL(8,4),
    LOWPRICE   DECIMAL(8,4),
    VOLUME     INTEGER,
    PRIMARY KEY (COMPANY, SNAPDATE)
);

-- Q6. Load DAILY from STOCK.
INSERT INTO DAILY (COMPANY, SNAPDATE, HIGHPRICE, LOWPRICE, VOLUME)
SELECT COMPANY, SNAPDATE, MAX(HIGHPRICE), MIN(LOWPRICE), SUM(VOLUME)
  FROM STOCK
 GROUP BY COMPANY, SNAPDATE;

SELECT * FROM DAILY ORDER BY COMPANY, SNAPDATE;

-- Q7. Company master data. Every fact in the case gets a column,
-- including IEG03's manufacturing building. Only ID and name are known for all three.
CREATE TABLE COMPANY (
    COMPANY    CHAR(5)      NOT NULL,
    NAME       VARCHAR(50)  NOT NULL,
    ADDRESS    VARCHAR(50),
    CITY       VARCHAR(30),
    STATE      VARCHAR(30),
    COUNTRY    VARCHAR(30),
    FISCALID   VARCHAR(20),
    EMPLOYEES  INTEGER,
    STOCKS     INTEGER,
    FACILITY   VARCHAR(50),
    PRIMARY KEY (COMPANY)
);

INSERT INTO COMPANY (COMPANY, NAME, ADDRESS, CITY, STATE, COUNTRY, FISCALID, EMPLOYEES, STOCKS, FACILITY)
VALUES ('IEG01', 'IE Merchant', 'Maria de Molina 32B', 'Madrid', NULL, 'Spain', 'B83812345', 12, 100000, NULL),
       ('IEG02', 'IE Exclusive Club', 'Marble Street 250', 'Hartford', 'Connecticut', 'US', 'X234-123', 25, 248000, NULL),
       ('IEG03', 'IE International Souvenirs', NULL, 'Shanghai', NULL, 'China', NULL, 238, NULL, 'Manufacturing building');

-- Q8. Referential integrity. Added after COMPANY and DAILY are loaded,
-- so every existing STOCK row already has a parent.
-- Rule 1: deleting a company removes its DAILY and STOCK rows
ALTER TABLE DAILY
  ADD FOREIGN KEY (COMPANY) REFERENCES COMPANY (COMPANY)
  ON DELETE CASCADE;

ALTER TABLE STOCK
  ADD FOREIGN KEY (COMPANY) REFERENCES COMPANY (COMPANY)
  ON DELETE CASCADE;

-- Rule 2: deleting a company's day in DAILY removes that day's STOCK rows
ALTER TABLE STOCK
  ADD FOREIGN KEY (COMPANY, SNAPDATE) REFERENCES DAILY (COMPANY, SNAPDATE)
  ON DELETE CASCADE;

-- Q9. Deletes and their side effects. Run this check before and after each delete.
SELECT 'COMPANY' AS TABLE_NAME, COMPANY, COUNT(*) AS NUM_ROWS FROM COMPANY GROUP BY COMPANY
UNION ALL
SELECT 'DAILY', COMPANY, COUNT(*) FROM DAILY GROUP BY COMPANY
UNION ALL
SELECT 'STOCK', COMPANY, COUNT(*) FROM STOCK GROUP BY COMPANY
 ORDER BY TABLE_NAME, COMPANY;

-- 9.1 Removes 3 STOCK rows. No side effects: nothing depends on STOCK.
DELETE FROM STOCK
 WHERE COMPANY = 'IEG03' AND SNAPDATE = '2022-08-11'
   AND SNAPTIME BETWEEN '09:00:00' AND '09:59:59';

-- 9.2 Removes 38 STOCK rows. DAILY keeps its Aug 10 row (nothing recalculates it).
DELETE FROM STOCK
 WHERE COMPANY = 'IEG03' AND SNAPDATE = '2022-08-10';

-- 9.3 Removes 1 DAILY row and cascades to the 34 remaining STOCK rows for that day.
DELETE FROM DAILY
 WHERE COMPANY = 'IEG03' AND SNAPDATE = '2022-08-11';

-- 9.4 Removes 1 COMPANY row and cascades to 4 DAILY and 117 STOCK rows.
DELETE FROM COMPANY
 WHERE COMPANY = 'IEG03';
