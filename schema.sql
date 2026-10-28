-- ============================================================
-- Library Management System - Relational Schema
-- Module 2 Assignment - MSAI-5523
-- Dialect: SQLite (CHECK constraints + triggers for portability
--          when testing; notes below on adapting to other RDBMS)
-- ============================================================

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------
-- 1. BOOKS  (library inventory / catalog)
-- ------------------------------------------------------------
CREATE TABLE Books (
    BookID          INTEGER PRIMARY KEY,
    Title           TEXT    NOT NULL,
    Author          TEXT    NOT NULL,
    Genre           TEXT    NOT NULL,
    Format          TEXT    NOT NULL
                    CHECK (Format IN ('Hardback','Paperback','Audio book','E-book')),
    PublicationYear INTEGER NOT NULL
                    CHECK (PublicationYear > 0),   -- "not in the future" is enforced by a trigger below
                                                     -- (SQLite CHECK constraints must be deterministic)
    CallNumber      TEXT    NOT NULL UNIQUE,
    NumberOfCopies  INTEGER NOT NULL DEFAULT 1
                    CHECK (NumberOfCopies >= 0)
);

-- ------------------------------------------------------------
-- 2. MEMBERS  (customers)
-- ------------------------------------------------------------
CREATE TABLE Members (
    MemberID            INTEGER PRIMARY KEY,
    FirstName           TEXT    NOT NULL,
    LastName            TEXT    NOT NULL,
    Email               TEXT    NOT NULL UNIQUE
                        CHECK (Email LIKE '%_@_%._%'),
    Phone               TEXT,
    MembershipStartDate TEXT    NOT NULL,        -- ISO-8601 'YYYY-MM-DD'
    MembershipStatus    TEXT    NOT NULL DEFAULT 'Active'
                        CHECK (MembershipStatus IN ('Active','Suspended','Expired','Cancelled'))
);

-- ------------------------------------------------------------
-- 3. TRANSACTIONS  (circulation / check-in-check-out log)
-- ------------------------------------------------------------
CREATE TABLE Transactions (
    TransactionID INTEGER PRIMARY KEY,
    BookID        INTEGER NOT NULL REFERENCES Books(BookID),
    MemberID      INTEGER NOT NULL REFERENCES Members(MemberID),
    DateBorrowed  TEXT    NOT NULL,              -- ISO-8601 'YYYY-MM-DD'
    DueDate       TEXT    NOT NULL,
    DateReturned  TEXT,                          -- NULL until the book comes back
    LoanStatus    TEXT    NOT NULL DEFAULT 'Checked Out'
                  CHECK (LoanStatus IN ('Checked Out','Returned','Overdue','Lost')),

    CHECK (DueDate >= DateBorrowed),
    CHECK (DateReturned IS NULL OR DateReturned >= DateBorrowed),
    CHECK (
        (LoanStatus = 'Returned' AND DateReturned IS NOT NULL)
        OR (LoanStatus != 'Returned' AND DateReturned IS NULL)
    )
);

CREATE INDEX idx_transactions_book   ON Transactions(BookID);
CREATE INDEX idx_transactions_member ON Transactions(MemberID);

-- ============================================================
-- BUSINESS-RULE ENFORCEMENT (triggers)
-- Declarative CHECK/FK constraints above cover structural rules.
-- The rules below are "cross-row" rules (they depend on OTHER
-- rows), which SQLite can only express with triggers.
-- ============================================================

-- Rule: a book's publication year cannot be in the future.
-- (Expressed as a trigger, not a CHECK, because strftime('now') is
-- non-deterministic and SQLite CHECK constraints must be deterministic.)
CREATE TRIGGER trg_book_year_not_future
BEFORE INSERT ON Books
BEGIN
    SELECT RAISE(ABORT, 'PublicationYear cannot be in the future')
    WHERE NEW.PublicationYear > CAST(strftime('%Y','now') AS INTEGER);
END;

-- Rule: a member whose account is not Active may not check out a book.
CREATE TRIGGER trg_member_must_be_active
BEFORE INSERT ON Transactions
BEGIN
    SELECT RAISE(ABORT, 'Member is not Active and cannot borrow books')
    WHERE (SELECT MembershipStatus FROM Members WHERE MemberID = NEW.MemberID) != 'Active';
END;

-- Rule: a book cannot be checked out if no copies are currently available
-- (available = NumberOfCopies - copies currently Checked Out or Overdue).
CREATE TRIGGER trg_copy_must_be_available
BEFORE INSERT ON Transactions
BEGIN
    SELECT RAISE(ABORT, 'No available copies of this book')
    WHERE (
        (SELECT NumberOfCopies FROM Books WHERE BookID = NEW.BookID)
        - (SELECT COUNT(*) FROM Transactions
           WHERE BookID = NEW.BookID AND LoanStatus IN ('Checked Out','Overdue'))
    ) <= 0;
END;

-- Rule: a member may not have more than 5 books checked out at once.
CREATE TRIGGER trg_enforce_loan_limit
BEFORE INSERT ON Transactions
BEGIN
    SELECT RAISE(ABORT, 'Member already has the maximum of 5 books checked out')
    WHERE (
        SELECT COUNT(*) FROM Transactions
        WHERE MemberID = NEW.MemberID AND LoanStatus IN ('Checked Out','Overdue')
    ) >= 5;
END;

-- Rule: a member with any Overdue item may not check out additional books.
CREATE TRIGGER trg_block_borrow_if_overdue
BEFORE INSERT ON Transactions
BEGIN
    SELECT RAISE(ABORT, 'Member has an overdue item and cannot borrow more books')
    WHERE EXISTS (
        SELECT 1 FROM Transactions
        WHERE MemberID = NEW.MemberID AND LoanStatus = 'Overdue'
    );
END;

-- ============================================================
-- REPORTING VIEWS
-- ============================================================

-- Real-time copy availability per title.
CREATE VIEW BookAvailability AS
SELECT
    b.BookID,
    b.Title,
    b.NumberOfCopies,
    b.NumberOfCopies - COALESCE((
        SELECT COUNT(*) FROM Transactions t
        WHERE t.BookID = b.BookID AND t.LoanStatus IN ('Checked Out','Overdue')
    ), 0) AS AvailableCopies
FROM Books b;

-- Loans that are currently past their due date and not yet returned.
CREATE VIEW OverdueLoans AS
SELECT *
FROM Transactions
WHERE DateReturned IS NULL
  AND DueDate < date('now');

-- ------------------------------------------------------------
-- Notes on portability (SQL Server / PostgreSQL / MySQL):
--   * strftime('%Y','now') -> use a native current-year function
--     (YEAR(GETDATE()) / EXTRACT(YEAR FROM CURRENT_DATE)).
--   * date('now') -> CURRENT_DATE.
--   * RAISE(ABORT, 'msg') -> replace with a trigger body that
--     raises an error in that platform's procedural syntax
--     (RAISERROR / RAISE EXCEPTION / SIGNAL).
--   * Store date columns as DATE type rather than TEXT where the
--     engine supports it.
-- ------------------------------------------------------------
