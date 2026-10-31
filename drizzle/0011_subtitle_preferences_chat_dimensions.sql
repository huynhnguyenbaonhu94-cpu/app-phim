-- Nullable per-user subtitle preferences (JSON serialized in MEDIUMTEXT).
ALTER TABLE `users` ADD COLUMN `subtitlePreferences` mediumtext NULL;

-- Optional dimensions for newly uploaded special-chat media.
ALTER TABLE `special_chat_attachments`
  ADD COLUMN `mediaWidth` int NULL,
  ADD COLUMN `mediaHeight` int NULL;
