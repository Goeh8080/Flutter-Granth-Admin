-- Multiple admins: role + disabled flag. Existing rows (goutam) become owner; their hash/salt are NOT touched.
ALTER TABLE admins ADD COLUMN role TEXT NOT NULL DEFAULT 'admin';
ALTER TABLE admins ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE admins ADD COLUMN created_by TEXT;
UPDATE admins SET role = 'owner' WHERE username = 'goutam';
