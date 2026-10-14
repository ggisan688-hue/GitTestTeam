-- Preserve existing selections while converting legacy color names to HEX.
UPDATE change_book_ai_friend_highlight_colors SET highlight_color = CASE upper(trim(highlight_color))
 WHEN 'YELLOW' THEN '#FFF59D'
 WHEN 'PINK' THEN '#F8BBD0'
 WHEN 'GREEN' THEN '#A5D6A7'
 WHEN 'BLUE' THEN '#90CAF9'
 WHEN 'PURPLE' THEN '#CE93D8'
 WHEN 'ORANGE' THEN '#FFCC80'
 WHEN 'RED' THEN '#EF9A9A'
 WHEN 'MINT' THEN '#80CBC4'
 WHEN 'SKY' THEN '#B3E5FC'
 WHEN 'GRAY' THEN '#BDBDBD'
 WHEN 'PEACH' THEN '#FFCCBC'
 ELSE highlight_color END WHERE upper(trim(highlight_color)) IN ('YELLOW','PINK','GREEN','BLUE','PURPLE','ORANGE','RED','MINT','SKY','GRAY','PEACH');
UPDATE change_book_reading_notes SET highlight_color = CASE upper(trim(highlight_color))
 WHEN 'YELLOW' THEN '#FFF59D'
 WHEN 'PINK' THEN '#F8BBD0'
 WHEN 'GREEN' THEN '#A5D6A7'
 WHEN 'BLUE' THEN '#90CAF9'
 WHEN 'PURPLE' THEN '#CE93D8'
 WHEN 'ORANGE' THEN '#FFCC80'
 WHEN 'RED' THEN '#EF9A9A'
 WHEN 'MINT' THEN '#80CBC4'
 WHEN 'SKY' THEN '#B3E5FC'
 WHEN 'GRAY' THEN '#BDBDBD'
 WHEN 'PEACH' THEN '#FFCCBC'
 ELSE highlight_color END WHERE upper(trim(highlight_color)) IN ('YELLOW','PINK','GREEN','BLUE','PURPLE','ORANGE','RED','MINT','SKY','GRAY','PEACH');
UPDATE change_book_reading_room_notes SET highlight_color = CASE upper(trim(highlight_color))
 WHEN 'YELLOW' THEN '#FFF59D'
 WHEN 'PINK' THEN '#F8BBD0'
 WHEN 'GREEN' THEN '#A5D6A7'
 WHEN 'BLUE' THEN '#90CAF9'
 WHEN 'PURPLE' THEN '#CE93D8'
 WHEN 'ORANGE' THEN '#FFCC80'
 WHEN 'RED' THEN '#EF9A9A'
 WHEN 'MINT' THEN '#80CBC4'
 WHEN 'SKY' THEN '#B3E5FC'
 WHEN 'GRAY' THEN '#BDBDBD'
 WHEN 'PEACH' THEN '#FFCCBC'
 ELSE highlight_color END WHERE upper(trim(highlight_color)) IN ('YELLOW','PINK','GREEN','BLUE','PURPLE','ORANGE','RED','MINT','SKY','GRAY','PEACH');
ALTER TABLE change_book_ai_friend_highlight_colors ALTER COLUMN highlight_color SET DEFAULT '#FFF59D';
