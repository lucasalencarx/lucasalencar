import {env,mp,getRequest,apply} from '../_shared/server.ts';
import {verifySignature} from '../_shared/core.mjs';
Deno.serve(async req=>{if(req.method!=='POST')return new Response('POST only',{status:405});try{if(env('MP_ENABLED')!=='true')return new Response('Not enabled',{status:503});const url=new URL(req.url),id=url.searchParams.get('data.id')||'';
if(!await verifySignature(id,req.headers.get('x-request-id')||'',req.headers.get('x-signature')||'',env('MP_WEBHOOK_SECRET')))return new Response('Invalid signature',{status:401});
const body=await req.json();if(body.type!=='payment'||String(body.data?.id)!==id)return new Response('Ignored',{status:200});const p=await mp('/v1/payments/'+id);
if(!/^[0-9a-f-]{36}$/i.test(p.external_reference||''))return new Response('Unrelated payment',{status:200});
const r=await getRequest(p.external_reference);await apply(p,r);return new Response('OK',{status:200});
}catch{console.error('mp-webhook: falha de validação ou persistência; solicitação será repetida pelo provedor.');return new Response('Retry later',{status:500})}});
