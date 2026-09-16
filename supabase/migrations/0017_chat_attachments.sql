-- Chat attachments: the attach-file button in ChatScreen previously just
-- showed a "coming soon" snackbar. This adds the column the app needs to
-- actually send an image in a chat.
alter table public.messages add column if not exists attachment_url text;
