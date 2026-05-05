// =============================================================
// Supabase Edge Function: on-signup
// Deploy: supabase functions deploy on-signup --no-verify-jwt
//
// Configure o webhook em:
//   Supabase Dashboard → Auth → Hooks → "After user created"
//   → URL: https://SEU_PROJETO.supabase.co/functions/v1/on-signup
//
// Esta função recebe o evento após confirmação de e-mail e cria
// o workspace + profile para novos usuários que se auto-registraram.
// Para convites (invite flow), use a função adicionar_membro() no RPC.
// =============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const sb = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const jsonOk = (msg: string) =>
  new Response(JSON.stringify({ message: msg }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const user = body.record ?? body.user;
    if (!user?.id) return jsonOk('no user id');

    // Se o usuário já tem um profile, é um convite — não cria novo workspace
    const { data: existing } = await sb
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .single();

    if (existing) return jsonOk('profile already exists');

    // Auto-registro: cria um workspace próprio
    const nome = user.user_metadata?.nome_oficina || 'Minha Oficina';
    const slug = nome.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + Date.now();

    await sb.rpc('criar_workspace', {
      p_user_id:   user.id,
      p_nome:      nome,
      p_slug:      slug,
      p_user_nome: user.user_metadata?.nome || user.email,
      p_username:  user.user_metadata?.username || user.email?.split('@')[0],
    });

    return jsonOk('workspace created');
  } catch (e) {
    console.error('on-signup error:', e);
    return new Response(JSON.stringify({ error: e.message }), {
      status: 200, // retornar 200 para não bloquear o signup
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
