-- Create library_media table for media metadata
CREATE TABLE IF NOT EXISTS library_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid NOT NULL REFERENCES coaches(id) ON DELETE CASCADE,
  filename text NOT NULL,
  file_type text NOT NULL CHECK (file_type IN ('video', 'image', 'document')),
  file_url text NOT NULL,
  file_size_bytes bigint,
  mime_type text,
  tags text[] DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_library_media_coach_id ON library_media(coach_id);
CREATE INDEX IF NOT EXISTS idx_library_media_file_type ON library_media(file_type);
CREATE INDEX IF NOT EXISTS idx_library_media_tags ON library_media USING gin(tags);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_library_media_updated_at ON library_media;
CREATE TRIGGER update_library_media_updated_at
  BEFORE UPDATE ON library_media
  FOR EACH ROW
  EXECUTE FUNCTION update_client_updated_at();

-- Enable RLS
ALTER TABLE library_media ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Coaches can view their own media" ON library_media;
CREATE POLICY "Coaches can view their own media"
  ON library_media FOR SELECT
  USING (coach_id = auth.uid());

DROP POLICY IF EXISTS "Coaches can insert their own media" ON library_media;
CREATE POLICY "Coaches can insert their own media"
  ON library_media FOR INSERT
  WITH CHECK (coach_id = auth.uid());

DROP POLICY IF EXISTS "Coaches can update their own media" ON library_media;
CREATE POLICY "Coaches can update their own media"
  ON library_media FOR UPDATE
  USING (coach_id = auth.uid());

DROP POLICY IF EXISTS "Coaches can delete their own media" ON library_media;
CREATE POLICY "Coaches can delete their own media"
  ON library_media FOR DELETE
  USING (coach_id = auth.uid());

-- Create storage bucket for media files
INSERT INTO storage.buckets (id, name, public)
VALUES ('media_library', 'media_library', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for media_library bucket
DROP POLICY IF EXISTS "Coaches can upload to their folder" ON storage.objects;
CREATE POLICY "Coaches can upload to their folder"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'media_library' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Coaches can view their files" ON storage.objects;
CREATE POLICY "Coaches can view their files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'media_library'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Coaches can delete their files" ON storage.objects;
CREATE POLICY "Coaches can delete their files"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'media_library'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );