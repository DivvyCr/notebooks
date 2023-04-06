CREATE TABLE books (
  id INTEGER GENERATED ALWAYS AS IDENTITY,
  code VARCHAR(5) NOT NULL CHECK (code ~ '^[a-zA-Z0-9_\-]+$'), /* don't allow whitespace */
  title VARCHAR(50) NOT NULL,
  description VARCHAR(200) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE (code)
);

CREATE TABLE chapters (
  id INTEGER GENERATED ALWAYS AS IDENTITY,
  title VARCHAR(50) NOT NULL,
  content TEXT,
  PRIMARY KEY (id)
);

CREATE TABLE navigation (
  bookid           INTEGER NOT NULL,
  chapterid        INTEGER NOT NULL,
  parent_chapterid INTEGER NOT NULL,
  priority         INTEGER NOT NULL CHECK (priority > 0),
  FOREIGN KEY (bookid)           REFERENCES books(id),
  FOREIGN KEY (chapterid)        REFERENCES chapters(id),
  FOREIGN KEY (parent_chapterid) REFERENCES chapters(id),
  UNIQUE (bookid, chapterid)
);

CREATE VIEW chapter_links AS
SELECT
  b.id AS bookid,
  c.id AS chapterid,
  '/' || b.code || '/' || REPLACE(LOWER(c.title), ' ', '-') AS link
FROM
  navigation n
  JOIN books b ON n.bookid = b.id
  JOIN chapters c ON n.chapterid = c.id;

CREATE VIEW chapters_tree AS
WITH RECURSIVE cte AS (
    SELECT
	bookid,
        chapterid,
        parent_chapterid,
        priority::TEXT AS agg_priority
    FROM navigation
    WHERE parent_chapterid = chapterid
  UNION ALL
    SELECT
	nav.bookid,
        nav.chapterid,
        nav.parent_chapterid,
        cte.agg_priority || '.' || nav.priority
    FROM
        cte
        JOIN navigation nav ON cte.chapterid = nav.parent_chapterid AND cte.chapterid != nav.chapterid
)
SELECT
  b.id    AS bookid,
  b.code  AS book_code,
  c.id    AS chapterid,
  c.title AS chapter_title,
  cte.parent_chapterid,
  agg_priority
FROM
    cte
    JOIN chapters c ON c.id = cte.chapterid
    JOIN books    b ON b.id = cte.bookid
ORDER BY agg_priority;

CREATE OR REPLACE VIEW chapters_navtree AS
WITH children_cte AS (
  SELECT
    parent_chapterid,
    array_agg(chapterid) AS children
  FROM navigation
  WHERE parent_chapterid != chapterid
  GROUP BY parent_chapterid
)
SELECT
  t.bookid,
  t.book_code,
  t.chapterid,
  t.chapter_title,
  t.parent_chapterid,
  c.children,
  l.link,
  t.agg_priority /* to allow re-ordering */
FROM
  chapters_tree t
  JOIN chapter_links l ON l.chapterid = t.chapterid
  LEFT OUTER JOIN children_cte c ON c.parent_chapterid = t.chapterid;

CREATE OR REPLACE VIEW first_chapters AS
WITH cte AS (
  SELECT
    bookid,
    book_code,
    chapterid,
    agg_priority,
    ROW_NUMBER() OVER (PARTITION BY bookid ORDER BY agg_priority) AS top
  FROM chapters_tree
)
SELECT
  cte.book_code,
  cte.chapterid,
  l.link,
  cte.agg_priority
FROM
  cte
  JOIN chapter_links l ON cte.chapterid = l.chapterid
WHERE top = 1;

/* ============================================================================================== */

CREATE OR REPLACE FUNCTION create_book(bookCode VARCHAR(5), bookTitle VARCHAR(50), bookDescription VARCHAR(200))
  RETURNS INTEGER AS $$
DECLARE
  new_bookid INTEGER;
BEGIN
  INSERT INTO books (code, title, description) VALUES (bookCode, bookTitle, bookDescription) RETURNING id INTO new_bookid;
  PERFORM create_chapter(new_bookid, NULL, bookCode || ' Intro', ''); /* PERFORM instead of SELECT since we are ignoring return value */

  RETURN new_bookid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_book(bookId INTEGER, newBookCode VARCHAR(5), newBookTitle VARCHAR(50), newBookDescription VARCHAR(200))
  AS $$
BEGIN
  UPDATE books
  SET
    code = newBookCode,
    title = newBookTitle,
    description = newBookDescription
  WHERE id = bookId;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE delete_book(deleteBookId INTEGER)
  AS $$
BEGIN
  DELETE FROM chapters c
  USING navigation n
  WHERE n.bookid = deleteBookId AND c.id = n.chapterid;
  
  DELETE FROM books WHERE id = deleteBookId;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION append_chapter(precedingId INTEGER, chapterTitle VARCHAR(50), chapterContent TEXT)
  RETURNS INTEGER AS $$
DECLARE
  new_bookid INTEGER;
  new_chapterid INTEGER;
BEGIN
  SELECT bookid FROM navigation WHERE chapterid = precedingId INTO new_bookid;
  SELECT create_chapter(new_bookid, precedingId, chapterTitle, chapterContent) INTO new_chapterid;
  RETURN new_chapterid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_chapter(bookId INTEGER, precedingId INTEGER, chapterTitle VARCHAR(50), chapterContent TEXT)
  RETURNS INTEGER AS $$
DECLARE
  new_chapterid INTEGER;
  new_parentid INTEGER;
  new_priority INTEGER;
BEGIN
  INSERT INTO chapters (title, content) VALUES (chapterTitle, chapterContent) RETURNING id INTO new_chapterid;

  IF precedingId IS NULL THEN
    SELECT 1             INTO new_priority;
    SELECT new_chapterid INTO new_parentid;
   ELSE
     SELECT priority+1       FROM navigation WHERE chapterid = precedingId INTO new_priority;
     SELECT parent_chapterid FROM navigation WHERE chapterid = precedingId INTO new_parentid;
   END IF;
  
  UPDATE navigation SET priority = priority+1 WHERE priority >= new_priority AND (parent_chapterid = new_parentid OR (parent_chapterid IS NULL AND new_parentid IS NULL));
  INSERT INTO navigation (bookid, chapterid, parent_chapterid, priority) VALUES (bookId, new_chapterid, new_parentid, new_priority);

  RETURN new_chapterid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_chapter(chapterId INTEGER, newChapterTitle VARCHAR(50), newChapterContent TEXT)
  AS $$
BEGIN
  UPDATE chapters
  SET
    title = newChapterTitle,
    content = newChapterContent
  WHERE id = chapterId;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE delete_chapter(deleteChapterId INTEGER)
  AS $$
DECLARE
  delete_bookid INTEGER;
  delete_parentid INTEGER;
  delete_priority INTEGER;
BEGIN
  /* Ensure at least one chapter remains: */
  
  SELECT bookid FROM navigation WHERE chapterid = deleteChapterId INTO delete_bookid;
  IF (SELECT COUNT(*) FROM navigation WHERE bookid = delete_bookid) <= 1
  THEN RETURN;
  END IF;

  /* Carry out deletion: */
  
  SELECT priority         FROM navigation WHERE chapterid = deleteChapterId INTO delete_priority;
  SELECT parent_chapterid FROM navigation WHERE chapterid = deleteChapterId INTO delete_parentid;
  
  UPDATE navigation
  SET priority = priority-1
  WHERE priority >= delete_priority AND (parent_chapterid = delete_parentid OR (parent_chapterid IS NULL AND delete_parentid IS NULL));

  DELETE FROM navigation WHERE chapterid = deleteChapterId;
  DELETE FROM chapters WHERE id = deleteChapterId;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE move_chapter(moveChapterId INTEGER, newParentId INTEGER, newPrecedingId INTEGER)
  AS $$
DECLARE
  old_parentid INTEGER;
  old_priority INTEGER;
  new_priority INTEGER;
  priority_shift INTEGER;
BEGIN
  SELECT priority      FROM navigation WHERE chapterid = moveChapterId INTO old_priority;
  SELECT parent_chapterid FROM navigation WHERE chapterid = moveChapterId INTO old_parentid;

  IF newParentId IS NULL THEN
    SELECT moveChapterId INTO newParentId;
  END IF;

  IF newPrecedingId IS NULL THEN
    SELECT 1 INTO new_priority;
  ELSE
    SELECT priority+1 FROM navigation WHERE chapterid = newPrecedingId INTO new_priority;
  END IF;

  IF old_parentid = newParentId THEN
    IF new_priority > old_priority THEN
      SELECT -1 INTO priority_shift;
    END IF;
    IF new_priority < old_priority THEN
      SELECT 1 INTO priority_shift;
    END IF;

    UPDATE navigation SET priority = priority + priority_shift WHERE priority <= new_priority AND priority > old_priority AND parent_chapterid = newParentId;
  ELSE
    UPDATE navigation SET priority = priority-1 WHERE priority >  old_priority AND parent_chapterid = old_parentid;
    UPDATE navigation SET priority = priority+1 WHERE priority >= new_priority AND parent_chapterid = newParentId;
  END IF;

  UPDATE navigation SET parent_chapterid = newParentId, priority = new_priority WHERE chapterid = moveChapterId;
END;
$$ LANGUAGE plpgsql;

