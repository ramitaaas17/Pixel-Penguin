const { chromium } = require('../.tools/web-test/node_modules/playwright');
const { randomBytes } = require('crypto');
const { execFileSync } = require('child_process');
const fs = require('fs');
const assert = require('assert/strict');
const base = 'http://localhost:3000';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, label, timeout = 25000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { if (predicate()) return; await pause(150); }
  throw new Error('Tiempo agotado: ' + label);
}
function track(page) {
  const state = {events: [], sent: [], errors: [], token: '', closes: 0};
  page.on('pageerror', error => state.errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && !message.text().includes('401 (Unauthorized)')) state.errors.push(message.text());
  });
  page.on('websocket', socket => {
    socket.on('framereceived', ({payload}) => {
      try { state.events.push(JSON.parse(payload.toString())); } catch {}
    });
    socket.on('framesent', ({payload}) => {
      try {
        const data = JSON.parse(payload.toString());
        if (data.type === 'auth') state.token = data.token;
        else state.sent.push(data);
      } catch {}
    });
    socket.on('close', () => state.closes++);
  });
  return state;
}
async function typeSpanish(page, text) {
  const keys = await page.context().newCDPSession(page);
  for (const character of text) {
    if (character.codePointAt(0) < 128) await page.keyboard.type(character);
    else {
      await keys.send('Input.dispatchKeyEvent', {type:'keyDown', key:character, text:character, unmodifiedText:character});
      await keys.send('Input.dispatchKeyEvent', {type:'keyUp', key:character});
    }
  }
  await keys.detach();
}
async function login(page, account) {
  await page.goto(base);
  await page.waitForFunction(() => !document.getElementById('status'), null, {timeout:60000});
  await pause(600);
  await page.keyboard.press('Enter');
  await pause(400);
  await page.keyboard.type(account.username);
  await page.keyboard.press('Enter');
  await page.keyboard.type(account.password);
  const result = page.waitForResponse(r => r.url().endsWith('/auth/login'));
  await page.keyboard.press('Enter');
  assert.equal((await result).status(), 200);
}
(async () => {
  fs.mkdirSync('docs/social', {recursive:true});
  const fixtures = [];
  let browser;
  try {
    for (let i=0;i<2;i++) {
      const account = {username:'chat_'+randomBytes(6).toString('hex'),password:randomBytes(16).toString('hex')};
      const response = await fetch(base+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(account)});
      assert.equal(response.status,201);
      const session = await response.json();
      fixtures.push({...account, id:session.jugador.id, token:session.token});
    }
    browser = await chromium.launch({headless:true,args:['--enable-unsafe-swiftshader','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
    const contextA = await browser.newContext({viewport:{width:960,height:600}});
    const contextB = await browser.newContext({viewport:{width:960,height:600}});
    const a = await contextA.newPage(), b = await contextB.newPage();
    const one = track(a), two = track(b);
    await login(a,fixtures[0]);
    await until(()=>one.events.some(e=>e.type==='welcome'),'primera conexión');
    await login(b,fixtures[1]);
    await until(()=>two.events.some(e=>e.type==='welcome'),'segunda conexión');
    await until(()=>one.events.some(e=>e.type==='joined'&&e.player.id===fixtures[1].id),'presencia entre clientes');
    assert(two.events.find(e=>e.type==='welcome').players.some(p=>p.id===fixtures[0].id));
    console.log('PASS dos juegos Godot independientes comparten presencia autenticada');
    await b.mouse.click(590,435);
    await until(()=>one.events.some(e=>e.type==='moved'&&e.player.id===fixtures[1].id&&Math.abs(e.player.x+32)>12),'movimiento remoto');
    await pause(2000);
    await a.screenshot({path:'docs/social/two-players.png'});
    console.log('PASS el movimiento de un jugador llega al otro cliente');
    await a.bringToFront();
    await a.keyboard.press('Enter');
    await pause(400);
    await a.screenshot({path:'docs/social/chat-open.png'});
    await typeSpanish(a, 'Hola, ¿cómo están los pingüinos?');
    const movementBefore = one.sent.filter(e=>e.type==='move').length;
    await a.keyboard.type(' e');
    await pause(400);
    assert.equal(one.sent.filter(e=>e.type==='move').length,movementBefore);
    await a.keyboard.press('Enter');
    await until(()=>two.events.some(e=>e.type==='chat'&&e.message.text.includes('pingüinos')),'chat primer cliente');
    const received = two.events.find(e=>e.type==='chat'&&e.message.text.includes('pingüinos')).message;
    assert.equal(received.playerId,fixtures[0].id);
    assert.equal(received.name,fixtures[0].username);
    await b.bringToFront();
    await b.keyboard.press('Enter');
    await pause(400);
    await typeSpanish(b, '¡Hola! Ya te veo en la plaza.');
    await b.keyboard.press('Enter');
    await until(()=>one.events.some(e=>e.type==='chat'&&e.message.playerId===fixtures[1].id),'respuesta segundo cliente');
    await until(()=>two.events.some(e=>e.type==='chat'&&e.message.playerId===fixtures[1].id),'eco confirmado al emisor');
    const chatOne=one.events.filter(e=>e.type==='chat'&&fixtures.some(f=>f.id===e.message.playerId)).map(e=>e.message.sequence);
    const chatTwo=two.events.filter(e=>e.type==='chat'&&fixtures.some(f=>f.id===e.message.playerId)).map(e=>e.message.sequence);
    assert.deepEqual(chatOne,chatTwo);
    await pause(700);
    await a.screenshot({path:'docs/social/chat-a.png'});
    await b.screenshot({path:'docs/social/chat-b.png'});
    console.log('PASS mensajes bidireccionales con mismo orden e identidad; escribir E no mueve al jugador');
    await a.setViewportSize({width:1920,height:1200});
    await pause(500);
    await a.screenshot({path:'docs/social/chat-scale2.png'});
    await a.setViewportSize({width:960,height:600});
    const oldEpoch=one.events.find(e=>e.type==='welcome').epoch;
    const welcomesA=one.events.filter(e=>e.type==='welcome').length;
    const welcomesB=two.events.filter(e=>e.type==='welcome').length;
    execFileSync('docker',['compose','restart','middleware'],{stdio:'pipe'});
    await until(()=>one.events.filter(e=>e.type==='welcome').length>welcomesA,'reconexión cliente A',40000);
    await until(()=>two.events.filter(e=>e.type==='welcome').length>welcomesB,'reconexión cliente B',40000);
    assert.notEqual(one.events.filter(e=>e.type==='welcome').at(-1).epoch,oldEpoch);
    await until(()=>one.events.slice(one.events.findLastIndex(e=>e.type==='welcome')).some(e=>e.type==='joined'&&e.player.id===fixtures[1].id)||one.events.filter(e=>e.type==='welcome').at(-1).players.length===2,'restauración de presencia');
    console.log('PASS ambos juegos reconectan y reconstruyen la sala tras reiniciar el servidor');
    const leftIndex=one.events.length;
    const logout=await fetch(base+'/auth/logout',{method:'POST',headers:{Authorization:'Bearer '+two.token}});
    assert.equal(logout.status,200);
    await until(()=>one.events.slice(leftIndex).some(e=>e.type==='left'&&e.playerId===fixtures[1].id),'salida tras revocación',15000);
    console.log('PASS revocar sesión desconecta el chat y elimina la presencia');
    await b.close();
    const probe=await contextB.newPage();
    await probe.goto(base+'/heartbeat');
    const protocol = await probe.evaluate(async ({token})=>{
      const connect = token => new Promise((resolve,reject)=>{
        const socket=new WebSocket(location.origin.replace('http','ws')+'/plaza');
        const result={socket,events:[],closeCode:0};
        socket.onopen=()=>socket.send(JSON.stringify({type:'auth',token}));
        socket.onmessage=e=>{const event=JSON.parse(e.data);result.events.push(event);if(event.type==='welcome')resolve(result);};
        socket.onclose=e=>{result.closeCode=e.code;if(!result.events.some(e=>e.type==='welcome'))resolve(result);};
        socket.onerror=()=>reject(new Error('Fallo WebSocket de prueba'));
      });
      const invalid=await connect('A'.repeat(43));
      const valid=await connect(token);
      valid.socket.send(JSON.stringify({type:'chat',text:'No suplantes',name:'Falso'}));
      valid.socket.send(JSON.stringify({type:'chat',text:'x'.repeat(181)}));
      valid.socket.send(JSON.stringify({type:'move',x:300,y:0}));
      await new Promise(resolve=>setTimeout(resolve,700));
      const errors=valid.events.filter(e=>e.type==='error').length;
      const correction=valid.events.some(e=>e.type==='correction');
      valid.socket.close();
      return {invalid:invalid.closeCode,errors,correction};
    },{token:fixtures[0].token});
    assert.equal(protocol.invalid,4001);
    assert.equal(protocol.errors,2);
    assert(protocol.correction);
    await until(()=>one.closes>=2,'reemplazo de ventana');
    const sentCount=one.sent.length;
    await pause(2500);
    assert.equal(one.sent.length,sentCount);
    console.log('PASS token falso, suplantación, texto excesivo y teletransporte rechazados; sin bucle al abrir otra ventana');
    assert.deepEqual(one.errors,[]);
    assert.deepEqual(two.errors,[]);
    console.log('SOCIAL_VALIDATION failures=0');
  } finally {
    if(browser) await browser.close();
    for(const fixture of fixtures) {
      if(!/^chat_[a-f0-9]{12}$/.test(fixture.username)) throw new Error('Fixture no válido');
      const sql=`BEGIN; DELETE FROM accounts WHERE username='${fixture.username}'; DELETE FROM jugadores WHERE id=${fixture.id} AND nombre='${fixture.username}'; COMMIT;`;
      execFileSync('docker',['compose','exec','-T','db-jugadores','psql','-U','jugadoresapp','-d','jugadoresdb','-v','ON_ERROR_STOP=1','-c',sql],{stdio:'pipe'});
    }
    console.log('PASS cuentas temporales eliminadas');
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
