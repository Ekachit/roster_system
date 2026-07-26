const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const env = {
  supabaseUrl: url ?? 'http://127.0.0.1:54321',
  supabaseAnonKey: anonKey ?? 'local-development-placeholder',
  isConfigured: Boolean(url && anonKey),
}
