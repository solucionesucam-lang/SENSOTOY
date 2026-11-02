import { createClient } from '@supabase/supabase-js'
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js'

// Un unico cliente compartido por toda la app
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
