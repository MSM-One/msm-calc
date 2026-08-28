-- Enable Realtime replication for item_sizes and materials tables
ALTER PUBLICATION supabase_realtime ADD TABLE item_sizes, materials;
