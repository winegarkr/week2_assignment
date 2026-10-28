"""
Verification script for schema.sql.
Loads the schema, inserts the sample Books data (with two gaps filled in
as noted to the user), adds a couple of Members, and then runs a series
of INSERTs into Transactions that should each clearly PASS or FAIL
according to the business rules, printing a pass/fail report.
"""
import sqlite3
import sys

con = sqlite3.connect(":memory:")
con.execute("PRAGMA foreign_keys = ON;")
cur = con.cursor()

with open("schema.sql") as f:
    schema_sql = f.read()
cur.executescript(schema_sql)

# ---- Books (gaps filled per assumption stated to the user) ----
books = [
    (1, "The Hobbit", "J.R.R Tolkien", "Fantasy", "Hardback", 1937, "FIC FAN H1234", 2),
    (2, "The Name of the Wind (Kingkiller Chronicle Book 1)", "Patrick Rothfuss", "Fantasy", "Audio book", 2009, "FIC FAN A23", 1),
    (3, "7 Rules of Power", "Jeffrey Pfeffer", "Career Success", "Paperback", 2022, "NF ED P5555", 2),
    (4, "Sunrise on the Reaping", "Suzanne Collins", "Science Fiction", "Hardback", 2025, "FIC YA H6565", 4),
    (5, "The Anxious Generation", "Jonathan Haidt", "Personal Development", "Audio book", 2024, "NF ED A28", 1),
]
cur.executemany(
    "INSERT INTO Books (BookID,Title,Author,Genre,Format,PublicationYear,CallNumber,NumberOfCopies) "
    "VALUES (?,?,?,?,?,?,?,?)",
    books,
)

# ---- Members ----
members = [
    (1, "Ava", "Nguyen", "ava.nguyen@example.com", "555-0101", "2024-01-15", "Active"),
    (2, "Ben", "Carter", "ben.carter@example.com", "555-0102", "2023-06-01", "Suspended"),
]
cur.executemany(
    "INSERT INTO Members (MemberID,FirstName,LastName,Email,Phone,MembershipStartDate,MembershipStatus) "
    "VALUES (?,?,?,?,?,?,?)",
    members,
)
con.commit()

results = []


def try_insert(label, sql, params):
    try:
        cur.execute(sql, params)
        con.commit()
        results.append((label, "INSERTED", None))
    except sqlite3.IntegrityError as e:
        con.rollback()
        results.append((label, "REJECTED", str(e)))


# 1. Valid checkout -> should succeed
try_insert(
    "1. Active member borrows an available book",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (1,1,1,'2026-10-01','2026-10-22','Checked Out')",
    (),
)

# 2. Suspended member tries to borrow -> should be rejected
try_insert(
    "2. Suspended member attempts to borrow (should be rejected)",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (2,2,2,'2026-10-01','2026-10-22','Checked Out')",
    (),
)

# 3. Second copy of book 1 to a would-be third member not in table -> FK violation expected
try_insert(
    "3. Transaction references a nonexistent MemberID (should be rejected: FK)",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (3,1,99,'2026-10-01','2026-10-22','Checked Out')",
    (),
)

# 4. Borrow the last available copy of book 2 (only 1 copy, none checked out yet) -> succeeds
try_insert(
    "4. Active member borrows the only copy of book 2",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (4,2,1,'2026-10-01','2026-10-22','Checked Out')",
    (),
)

# 5. Try to borrow book 2 again (no copies left) -> should be rejected
try_insert(
    "5. Another checkout of book 2 with zero copies left (should be rejected)",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (5,2,1,'2026-10-02','2026-10-23','Checked Out')",
    (),
)

# 6. LoanStatus/DateReturned consistency: mark Returned but no DateReturned -> should be rejected
try_insert(
    "6. LoanStatus='Returned' with no DateReturned (should be rejected)",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,LoanStatus) "
    "VALUES (6,3,1,'2026-10-01','2026-10-22','Returned')",
    (),
)

# 7. Valid return (DateReturned set, status Returned) -> succeeds
try_insert(
    "7. Valid return record (DateReturned + status consistent)",
    "INSERT INTO Transactions (TransactionID,BookID,MemberID,DateBorrowed,DueDate,DateReturned,LoanStatus) "
    "VALUES (7,3,1,'2026-09-01','2026-09-22','2026-09-20','Returned')",
    (),
)

print(f"{'TEST':70} {'RESULT':10} DETAIL")
all_ok = True
expected = {
    "1. Active member borrows an available book": "INSERTED",
    "2. Suspended member attempts to borrow (should be rejected)": "REJECTED",
    "3. Transaction references a nonexistent MemberID (should be rejected: FK)": "REJECTED",
    "4. Active member borrows the only copy of book 2": "INSERTED",
    "5. Another checkout of book 2 with zero copies left (should be rejected)": "REJECTED",
    "6. LoanStatus='Returned' with no DateReturned (should be rejected)": "REJECTED",
    "7. Valid return record (DateReturned + status consistent)": "INSERTED",
}
for label, outcome, detail in results:
    ok = expected[label] == outcome
    all_ok &= ok
    mark = "OK" if ok else "MISMATCH"
    print(f"{label:70} {outcome:10} [{mark}] {detail or ''}")

print()
print("Current BookAvailability view:")
for row in cur.execute("SELECT * FROM BookAvailability ORDER BY BookID"):
    print("  ", row)

print()
print("ALL CHECKS PASSED" if all_ok else "SOME CHECKS DID NOT MATCH EXPECTATIONS")
sys.exit(0 if all_ok else 1)
