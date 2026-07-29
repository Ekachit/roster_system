import { Buffer } from 'node:buffer'
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

function validateProductionEnvironment(urlValue: string | undefined, keyValue: string | undefined) {
  const missing = [
    !urlValue && 'VITE_SUPABASE_URL',
    !keyValue && 'VITE_SUPABASE_ANON_KEY',
  ].filter(Boolean)
  if (missing.length) {
    throw new Error(`Missing production environment variables: ${missing.join(', ')}`)
  }

  const url = new URL(urlValue as string)
  if (url.protocol !== 'https:') {
    throw new Error('VITE_SUPABASE_URL must use HTTPS for a production build.')
  }

  const key = keyValue as string
  if (key.startsWith('sb_secret_') || key.toLowerCase().includes('service_role')) {
    throw new Error('VITE_SUPABASE_ANON_KEY must be a publishable or legacy anon key, never a secret/service-role key.')
  }
  const payload = key.split('.')[1]
  if (payload) {
    try {
      const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { role?: string }
      if (decoded.role === 'service_role') {
        throw new Error('VITE_SUPABASE_ANON_KEY contains a service-role JWT.')
      }
    } catch (error) {
      if (error instanceof Error && error.message.includes('service-role')) throw error
    }
  }
}

export default defineConfig(({ mode }) => {
  if (mode === 'production') {
    const productionEnv = loadEnv(mode, process.cwd(), 'VITE_')
    validateProductionEnvironment(
      productionEnv.VITE_SUPABASE_URL,
      productionEnv.VITE_SUPABASE_ANON_KEY,
    )
  }

  return {
    plugins: [react()],
    test: {
      include: ['src/**/*.test.{ts,tsx}'],
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      css: true,
    },
  }
})
