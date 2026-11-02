#!/usr/bin/env python3
"""Mostra apenas IDs de chats privados do seu próprio bot. Não imprime o token."""
import getpass,json,urllib.request,urllib.error
secret=getpass.getpass('Token do seu bot (entrada oculta): ').strip()
try:
 with urllib.request.urlopen('https://api.telegram.org/bot'+secret+'/getUpdates',timeout=20) as r:
  data=json.load(r)
 chats={}
 for item in data.get('result',[]):
  chat=item.get('message',{}).get('chat',{})
  if chat.get('type')=='private':chats[chat['id']]=chat.get('first_name','Chat privado')
 if not chats:print('Nenhum chat privado encontrado. Abra seu bot, envie /start e execute novamente. Use um bot novo, sem webhook ativo.')
 for cid,name in chats.items():print(str(cid)+' — '+name)
except Exception:print('Não foi possível consultar. Confira token, internet e se o bot já possui webhook ativo.')
