# Library Management System — Business Rules

Module 2 Assignment, MSAI-5523

## 1. Overview

The library operates on three datasets (tables). Each row in a table is a
*record*, and each table is a collection of records about one kind of
thing — together they form the relational database that runs the library.

| Table | Purpose | What one record represents |
|---|---|---|
| `Books` | Inventory / catalog | One title held by the library, and how many physical/digital copies of it exist |
| `Members` | Customer registry | One person enrolled as a library member |
| `Transactions` | Circulation log | One borrow event — a single book loaned to a single member |

## 2. Entities and attributes

### 2.1 Books (inventory)

| Column | Type | Rule |
|---|---|---|
| BookID | Integer | Primary key, uniquely identifies the title record |
| Title | Text | Required |
| Author | Text | Required |
| Genre | Text | Required |
| Format | Text | Required; one of `Hardback`, `Paperback`, `Audio book`, `E-book` |
| PublicationYear | Integer | Required; must be greater than 0 and cannot be a future year |
| CallNumber | Text | Required and unique; the shelving location for this title |
| NumberOfCopies | Integer | Required; total copies the library owns, must be ≥ 0 |

**Note:** `BookID` identifies a *title*, not an individual physical copy.
`NumberOfCopies` tracks how many copies of that title exist; which of
those copies are currently out is derived from `Transactions` (see §3.2),
not stored as a separate counter, so the two numbers can never drift out
of sync.

### 2.2 Members (customers)

| Column | Type | Rule |
|---|---|---|
| MemberID | Integer | Primary key |
| FirstName | Text | Required |
| LastName | Text | Required |
| Email | Text | Required and unique; must look like a valid email address |
| Phone | Text | Optional |
| MembershipStartDate | Date | Required |
| MembershipStatus | Text | Required; one of `Active`, `Suspended`, `Expired`, `Cancelled`; defaults to `Active` |

### 2.3 Transactions (circulation / check-in-check-out)

| Column | Type | Rule |
|---|---|---|
| TransactionID | Integer | Primary key |
| BookID | Integer | Required; must reference an existing `Books` record |
| MemberID | Integer | Required; must reference an existing `Members` record |
| DateBorrowed | Date | Required |
| DueDate | Date | Required; must be on or after `DateBorrowed` |
| DateReturned | Date | Optional; set only when the book comes back |
| LoanStatus | Text | Required; one of `Checked Out`, `Returned`, `Overdue`, `Lost`; defaults to `Checked Out` |

## 3. Relationships

* One **Book** can appear in many **Transactions** over time (one-to-many).
* One **Member** can appear in many **Transactions** over time (one-to-many).
* Each **Transaction** ties exactly one Book to exactly one Member for one
  borrowing period — it is the junction/associative record that connects
  inventory to customers and makes the loan operation possible.

## 4. Operating (business) rules

### 4.1 Membership rules

* A member's email address is unique — no two members share one.
* Only members with `MembershipStatus = Active` may check out books.
  `Suspended`, `Expired`, and `Cancelled` members are blocked at checkout.

### 4.2 Inventory / availability rules

* "Available copies" for a title = `NumberOfCopies` minus the count of
  that title's transactions currently in status `Checked Out` or
  `Overdue`. This is calculated on demand (see the `BookAvailability`
  view in `schema.sql`), not stored, so it is always accurate.
* A checkout may not be recorded for a title with zero available copies.

### 4.3 Checkout / loan rules

* A member may not have more than **5** books checked out at the same
  time.
* A member with any `Overdue` loan may not check out additional books
  until that loan is resolved.
* `DueDate` must fall on or after `DateBorrowed`. The library's standard
  loan period is 21 days from `DateBorrowed`, used to compute `DueDate`
  at checkout time.

### 4.4 Return / status rules

* `DateReturned` is left blank while a loan is outstanding and is filled
  in only when the book is physically checked back in.
* `LoanStatus = Returned` is only valid once `DateReturned` is set; a
  loan cannot be marked `Returned` without a return date, and a loan
  with no return date cannot be marked `Returned`.
* A loan becomes `Overdue` when the current date passes `DueDate` and
  `DateReturned` is still blank. The `OverdueLoans` view in `schema.sql`
  identifies these in real time; day-to-day status updates (e.g. a nightly
  job that flips `Checked Out` rows to `Overdue` once they pass their due
  date) are an application-layer process that reads from this view.
* `LoanStatus = Lost` is a manual designation used when a book is not
  returned and is being written off; it removes the copy from being
  counted as available again until resolved (handled operationally, since
  `NumberOfCopies` would need to be decremented separately in that case).

## 5. Implementation

These rules are implemented as a runnable SQL schema in
[`schema.sql`](./schema.sql):

* Structural rules (data types, required fields, uniqueness, allowed
  value lists, foreign keys) are enforced with `PRIMARY KEY`, `UNIQUE`,
  `NOT NULL`, `CHECK`, and `REFERENCES` constraints.
* Cross-row rules that depend on *other* records — active-membership
  check, availability check, the 5-book loan limit, and the no-new-loans-
  while-overdue rule — are enforced with `BEFORE INSERT` triggers, since
  a single-row `CHECK` constraint cannot see other rows.
* `BookAvailability` and `OverdueLoans` are views used to answer the two
  questions the library staff need most often: "how many copies of this
  title are on the shelf right now?" and "which loans are currently late?"

The schema was tested (`verify_schema.py`) against seven scenarios:
a valid checkout, a suspended member being blocked, a nonexistent member
being blocked, exhausting the last copy of a title, a second checkout
being blocked once copies run out, an inconsistent return record being
blocked, and a valid return being accepted. All seven behaved as the
rules above require.
