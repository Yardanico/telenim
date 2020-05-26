import asyncdispatch, strutils, os, strformat

import mathexpr

import telenim

proc parseConfig(path: string): (string, string, string, string) = 
  let a = parseJson(staticRead(path))
  (
    a["phone"].getStr(),
    a{"password"}.getStr(""),
    a["api_id"].getStr(),
    a["api_hash"].getStr()
  )

# TODO: Use parsetoml with proper runtime config?
const (Phone, Password, ApiId, ApiHash) = parseConfig("config.json")

proc handleAuth(client: TdlibClient, update: Update): Future[bool] {.async.} = 
  result = true
  let authState = update.asAuthorizationState

  case authState.kind
  of asClosed:
    result = false
  
  of asWaitTdlibParameters:
    client.send(%*{
      "@type": "setTdlibParameters", "parameters": {
        "database_directory": "tdlib",
        "use_message_database": true,
        "use_secret_chats": true,
        "api_id": ApiId,
        "api_hash": ApiHash,
        "system_language_code": "en",
        "device_model": "Desktop",
        "system_version": "Linux",
        "application_version": "1.0",
        "enable_storage_optimizer": true
      }
    })
  of asWaitEncryptionKey:
    client.send(%*{"@type": "checkDatabaseEncryptionKey", "encryption_key": ""})
  of asWaitPhoneNumber:
    client.send(%*{"@type": "setAuthenticationPhoneNumber", "phone_number": Phone})
  of asWaitCode:
    stdout.write "enter auth code: "
    let code = stdin.readLine()
    client.send(%*{"@type": "checkAuthenticationCode", "code": code})
  of asWaitRegistration:
    echo "Registration not implemented yet"
    quit(1)
  of asWaitPassword:
    client.send(%*{"@type": "checkAuthenticationPassword", "password": Password})
  else:
    echo authState

import mathexpr

template editLastMsg(client: TdlibClient, msg: string) = 
  client.send(%*{
    "@type": "editMessageText",
    "chat_id": cid,
    "message_id": mid,
    "input_message_content": {
      "@type": "inputMessageText",
      "text": {
        "@type": "formattedText",
        "text": msg
      }
    }
  })

proc handleMsgUpdate(client: TdlibClient, update: Update): Future[bool] {.async.} = 
  result = true
  let msg = update.nmMessage
  if not msg.isOutgoing:
    return
  let cid = msg.chatId
  let mid = msg.id
  let msgText = if msg.content.kind == mText:
    msg.content.messageteText.text else: ""
  case msgText
  of ".status":
    client.editLastMsg("All up and running!")
  of ".version":
    const gitRev = 
      if dirExists(".git") and gorgeEx("git status").exitCode == 0:
        staticExec("git rev-parse HEAD")
      else: "unknown"

    client.editLastMsg fmt"""Telenim v0.1.0
    Git hash - {gitRev}
    Compiled on {CompileDate} {CompileTime}""".unindent
  else:
    discard
  if msgText.startsWith ".solve":
    let expr = msgText.split(".solve ")[1]
    let e = newEvaluator()
    
    try:
      let res = e.eval(expr)
      client.editLastMsg expr & " = " & $res
    except:
      client.editLastMsg "Not a valid math expression!"

proc handleEvent(client: TdlibClient, event: JsonNode): Future[bool] {.async.} =
  result = true
  let typ = event["@type"].getStr()
  if typ.startsWith("update"):
    try:
      let update = event.toCustom(Update)
      if update.kind == uAuthorizationState:
        result = await client.handleAuth(update)
      elif update.kind == uNewMessage:
        result = await client.handleMsgUpdate(update)
    except:
      echo event.pretty()

proc main {.async.} =
  let client = newTdlibClient()

  while true:
    let event = await client.getEvent()
    asyncCheck client.handleEvent(event)

waitFor main()