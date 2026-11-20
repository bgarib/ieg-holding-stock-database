"""Re-run the DB2 script on SQLite and check the results reported in the README.
SQLite cannot ADD FOREIGN KEY with ALTER TABLE, so the keys are declared up front."""
import csv, pathlib, re, sqlite3
ROOT = pathlib.Path(__file__).resolve().parents[1]
sql = (ROOT / "sql" / "ieg_holding_db2.sql").read_text()
stmts = [s.strip() for s in re.sub(r"--[^\n]*", "", sql).split(";") if s.strip()]
db = sqlite3.connect(":memory:", isolation_level=None); db.execute("PRAGMA foreign_keys = ON")
stock_ddl = next(s for s in stmts if s.startswith("CREATE TABLE STOCK")).rstrip(")").rstrip() + """,
    FOREIGN KEY (COMPANY) REFERENCES COMPANY (COMPANY) ON DELETE CASCADE,
    FOREIGN KEY (COMPANY, SNAPDATE) REFERENCES DAILY (COMPANY, SNAPDATE) ON DELETE CASCADE)"""
daily_ddl = next(s for s in stmts if s.startswith("CREATE TABLE DAILY")).rstrip(")").rstrip() + """,
    FOREIGN KEY (COMPANY) REFERENCES COMPANY (COMPANY) ON DELETE CASCADE)"""
db.execute(next(s for s in stmts if s.startswith("CREATE TABLE COMPANY")))
db.execute(next(s for s in stmts if s.startswith("INSERT INTO COMPANY")))
db.execute(daily_ddl); db.execute(stock_ddl)
db.execute("PRAGMA foreign_keys = OFF")  # load STOCK before DAILY exists, as in DB2
for f in sorted((ROOT / "data").glob("IEG0*.csv")):
    rows = [[None if v == "" else v for v in r.values()] for r in csv.DictReader(open(f))]
    db.executemany("INSERT INTO STOCK VALUES (?,?,?,?,?,?,?,?)", rows)
db.execute(next(s for s in stmts if s.startswith("INSERT INTO DAILY")))
db.execute("PRAGMA foreign_keys = ON")
q = lambda s: db.execute(s).fetchall()
pick = lambda start: next(s for s in stmts if s.startswith(start))
selects = [s for s in stmts if s.startswith("SELECT")]
assert [(r[0], r[3]) for r in q(selects[1])] == [("IEG01", 186), ("IEG02", 194), ("IEG03", 192)]
assert len(q(selects[2])) == 17, "Q3 should return 17 incomplete periods"
assert q(selects[3]) == [("IEG01", 58, 93, 28), ("IEG02", 69, 84, 37), ("IEG03", 77, 72, 40)]
assert len(q("SELECT * FROM DAILY")) == 15
check = selects[-1]
ieg03 = lambda: {r[0]: r[2] for r in q(check) if r[1] == "IEG03"}
expected = [{"COMPANY": 1, "DAILY": 5, "STOCK": 189}, {"COMPANY": 1, "DAILY": 5, "STOCK": 151},
            {"COMPANY": 1, "DAILY": 4, "STOCK": 117}, {}]
for stmt, exp in zip([s for s in stmts if s.startswith("DELETE")], expected):
    db.execute(stmt); assert ieg03() == exp, (stmt, ieg03())
print("All checks passed: Q2 counts, Q3 17 rows, Q4 counts, Q6 15 rows, Q9 cascade 192 > 189 > 151 > 117 > 0")
